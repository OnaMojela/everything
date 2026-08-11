import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Text that shrinks to fit its constraints instead of being cut off with an
/// ellipsis.
///
/// Used where the width is fixed by the layout but the content is not — stat
/// tiles showing "1h 40m" today and "13h 05m" next week, labels that are short
/// in English and long in another language. Ellipsising those reads as a bug:
/// "Total …" tells the reader nothing.
///
/// ### Why there is no polling loop
///
/// Nothing here runs on a timer. [LayoutBuilder] rebuilds precisely when the
/// available width changes — a rotation, a window resize, a font-scale change —
/// which is exactly when a re-measure is needed and never otherwise. A loop
/// checking "does this still fit?" every frame would do the same work sixty
/// times a second to reach the same answer, draining battery and competing
/// with the frame it is trying not to drop.
///
/// ### The cache
///
/// Measuring is the expensive part: each candidate size lays the string out
/// with a [TextPainter]. Results are memoised in a process-wide cache keyed by
/// the text, its style, the width it had to fit and the line budget, so the
/// same tile re-measures once and then never again — including across scrolls,
/// rebuilds and navigation. Repeat lookups are a map read.
class FittingText extends StatelessWidget {
  const FittingText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.minScale = 0.6,
  }) : assert(minScale > 0 && minScale <= 1);

  final String data;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  /// Floor on shrinking, as a fraction of the original size. Below this the
  /// text would be too small to read, so it ellipsises instead — shrinking
  /// without limit trades one unreadable result for another.
  final double minScale;

  @override
  Widget build(BuildContext context) {
    final resolved = style ?? DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = TextFitCache.instance.scaleFor(
          text: data,
          style: resolved,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          maxLines: maxLines,
          minScale: minScale,
          textScaler: scaler,
          textDirection: Directionality.of(context),
        );

        return Text(
          data,
          maxLines: maxLines,
          textAlign: textAlign,
          overflow: TextOverflow.ellipsis,
          style: resolved.copyWith(
            fontSize: (resolved.fontSize ?? 14) * scale,
          ),
        );
      },
    );
  }
}

/// Memoises "how much must this string shrink to fit?" answers.
///
/// Keyed on everything that can change the outcome. Bounded, because the
/// values being measured are live data — balances, durations, streak counts —
/// so an unbounded map would grow for the life of the process.
class TextFitCache {
  TextFitCache._();

  static final TextFitCache instance = TextFitCache._();

  /// Generous enough to hold every tile on screen many times over, small
  /// enough to stay negligible. Insertion-ordered, so the oldest entry is the
  /// cheapest to evict.
  static const maxEntries = 512;

  final LinkedHashMap<_FitKey, double> _cache = LinkedHashMap();

  int get length => _cache.length;

  @visibleForTesting
  void clear() => _cache.clear();

  double scaleFor({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required int maxLines,
    required double minScale,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    // An unbounded width can always fit the text, and rounding keeps a
    // fractional pixel difference from missing the cache every frame.
    if (!maxWidth.isFinite || maxWidth <= 0) return 1;

    final key = _FitKey(
      text: text,
      fontSize: style.fontSize ?? 14,
      fontWeight: style.fontWeight,
      fontFamily: style.fontFamily,
      letterSpacing: style.letterSpacing,
      width: maxWidth.roundToDouble(),
      height: maxHeight.isFinite ? maxHeight.roundToDouble() : double.infinity,
      maxLines: maxLines,
      minScale: minScale,
      textScale: textScaler.scale(1),
    );

    final hit = _cache.remove(key);
    if (hit != null) {
      // Reinsert so the most recently used entry is the last to be evicted.
      _cache[key] = hit;
      return hit;
    }

    final scale = _measure(
      key: key,
      style: style,
      textScaler: textScaler,
      textDirection: textDirection,
    );

    if (_cache.length >= maxEntries) _cache.remove(_cache.keys.first);
    _cache[key] = scale;
    return scale;
  }

  double _measure({
    required _FitKey key,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    bool fits(double scale) {
      final painter = TextPainter(
        text: TextSpan(
          text: key.text,
          style: style.copyWith(fontSize: key.fontSize * scale),
        ),
        maxLines: key.maxLines,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: key.width);

      final tooTall = key.height.isFinite && painter.height > key.height;
      return !painter.didExceedMaxLines && painter.width <= key.width && !tooTall;
    }

    if (fits(1)) return 1;

    // Binary search rather than stepping down: a handful of layouts instead of
    // dozens, and the result lands within half a percent of the largest size
    // that fits.
    var low = key.minScale;
    var high = 1.0;
    if (!fits(low)) return low;

    for (var i = 0; i < 8; i++) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

@immutable
class _FitKey {
  const _FitKey({
    required this.text,
    required this.fontSize,
    required this.fontWeight,
    required this.fontFamily,
    required this.letterSpacing,
    required this.width,
    required this.height,
    required this.maxLines,
    required this.minScale,
    required this.textScale,
  });

  final String text;
  final double fontSize;
  final FontWeight? fontWeight;
  final String? fontFamily;
  final double? letterSpacing;
  final double width;
  final double height;
  final int maxLines;
  final double minScale;
  final double textScale;

  @override
  bool operator ==(Object other) =>
      other is _FitKey &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.fontFamily == fontFamily &&
      other.letterSpacing == letterSpacing &&
      other.width == width &&
      other.height == height &&
      other.maxLines == maxLines &&
      other.minScale == minScale &&
      other.textScale == textScale;

  @override
  int get hashCode => Object.hash(text, fontSize, fontWeight, fontFamily,
      letterSpacing, width, height, maxLines, minScale, textScale);
}
