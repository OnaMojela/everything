import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'fitting_text.dart';

export 'fitting_text.dart' show FittingText, TextFitCache;

/// The standard surface of the app: a rounded, borderless card.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Tokens.s16),
    this.onTap,
    this.onLongPress,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.rCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
    return card;
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s8, 0, Tokens.s8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          ?trailing,
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: scheme.primary),
            ),
            const SizedBox(height: Tokens.s16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: Tokens.s8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: Tokens.s20),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated circular progress ring used for habits, budgets and goals.
class ProgressRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final double strokeWidth;
  final Color color;
  final Widget? center;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 44,
    this.strokeWidth = 4.5,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: Tokens.normal,
      curve: Tokens.curve,
      builder: (context, value, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                value: value,
                color: color,
                track: Theme.of(context).colorScheme.outlineVariant,
                stroke: strokeWidth,
              ),
            ),
            ?center,
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  _RingPainter({required this.value, required this.color, required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);
    if (value <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Horizontal bar showing progress with an over-limit state.
class ProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final double height;

  const ProgressBar({super.key, required this.progress, required this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final over = progress > 1.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: Tokens.normal,
        curve: Tokens.curve,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: height,
          backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          color: over ? Theme.of(context).colorScheme.error : color,
        ),
      ),
    );
  }
}

/// Rounded icon badge with tinted background — the app's signature list leading.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({super.key, required this.icon, required this.color, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, color: color, size: size * .5),
    );
  }
}

Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    ),
  );
}

/// Standard sheet scaffold: title row + content + optional primary action.
class SheetScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? titleTrailing;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actionLabel,
    this.onAction,
    this.titleTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
                ?titleTrailing,
              ],
            ),
            const SizedBox(height: Tokens.s16),
            ...children,
            if (actionLabel != null) ...[
              const SizedBox(height: Tokens.s24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ColorPickerRow extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;

  const ColorPickerRow({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemColors.length,
        separatorBuilder: (_, _) => const SizedBox(width: Tokens.s8),
        itemBuilder: (context, i) {
          final c = itemColors[i];
          final isSel = c.toARGB32() == selected.toARGB32();
          return GestureDetector(
            onTap: () => onChanged(c),
            child: AnimatedContainer(
              duration: Tokens.fast,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: isSel
                    ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
                    : null,
              ),
              child: isSel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
            ),
          );
        },
      ),
    );
  }
}

/// Icons used by seeded categories and other non-picker surfaces.
const _extraIcons = <IconData>[
  Icons.shopping_cart_rounded, Icons.subscriptions_rounded, Icons.category_rounded,
  Icons.card_giftcard_rounded, Icons.receipt_rounded, Icons.event_repeat_rounded,
  Icons.center_focus_strong_rounded, Icons.swap_horiz_rounded,
];

/// Resolve a stored codepoint back to a const [IconData] so Flutter's icon
/// tree-shaking keeps working. Falls back to a star for unknown codepoints.
IconData appIcon(int codePoint) {
  for (final i in pickerIcons) {
    if (i.codePoint == codePoint) return i;
  }
  for (final i in _extraIcons) {
    if (i.codePoint == codePoint) return i;
  }
  return Icons.star_rounded;
}

const pickerIcons = <IconData>[
  Icons.water_drop_rounded, Icons.menu_book_rounded, Icons.fitness_center_rounded,
  Icons.self_improvement_rounded, Icons.bedtime_rounded, Icons.directions_run_rounded,
  Icons.restaurant_rounded, Icons.local_cafe_rounded, Icons.brush_rounded,
  Icons.code_rounded, Icons.music_note_rounded, Icons.language_rounded,
  Icons.school_rounded, Icons.savings_rounded, Icons.credit_card_rounded,
  Icons.account_balance_rounded, Icons.account_balance_wallet_rounded, Icons.shopping_bag_rounded,
  Icons.home_rounded, Icons.directions_car_rounded, Icons.flight_takeoff_rounded,
  Icons.medication_rounded, Icons.favorite_rounded, Icons.pets_rounded,
  Icons.sports_esports_rounded, Icons.camera_alt_rounded, Icons.phone_iphone_rounded,
  Icons.laptop_mac_rounded, Icons.star_rounded, Icons.bolt_rounded,
  Icons.spa_rounded, Icons.cleaning_services_rounded, Icons.grass_rounded,
  Icons.currency_exchange_rounded, Icons.trending_up_rounded, Icons.work_rounded,
];

class IconPickerGrid extends StatelessWidget {
  final IconData selected;
  final Color color;
  final ValueChanged<IconData> onChanged;

  const IconPickerGrid({
    super.key,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Tokens.s8,
      runSpacing: Tokens.s8,
      children: [
        for (final icon in pickerIcons)
          GestureDetector(
            onTap: () => onChanged(icon),
            child: AnimatedContainer(
              duration: Tokens.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: icon == selected
                    ? color.withValues(alpha: .18)
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Tokens.rControl),
                border: icon == selected ? Border.all(color: color, width: 2) : null,
              ),
              child: Icon(icon,
                  size: 22,
                  color: icon == selected
                      ? color
                      : Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// GitHub-style contribution heatmap.
class HeatmapCalendar extends StatelessWidget {
  /// Map of day (date-only) to intensity 0..1.
  final Map<DateTime, double> data;
  final Color color;
  final int weeks;

  const HeatmapCalendar({super.key, required this.data, required this.color, this.weeks = 18});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayD = DateTime(now.year, now.month, now.day);
    // Align columns to weeks ending today.
    final end = todayD;
    final start = end.subtract(Duration(days: weeks * 7 - 1 + (end.weekday % 7)));
    final days = <DateTime>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    final columns = <List<DateTime>>[];
    for (var i = 0; i < days.length; i += 7) {
      columns.add(days.sublist(i, math.min(i + 7, days.length)));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in columns)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                children: [
                  for (final day in col)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Tooltip(
                        waitDuration: const Duration(milliseconds: 400),
                        message:
                            '${day.day}/${day.month}${(data[day] ?? 0) > 0 ? ' • ${((data[day] ?? 0) * 100).round()}%' : ''}',
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: _cellColor(data[day] ?? 0, scheme),
                            borderRadius: BorderRadius.circular(3.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _cellColor(double v, ColorScheme scheme) {
    if (v <= 0) return scheme.outlineVariant.withValues(alpha: .5);
    return color.withValues(alpha: .25 + .75 * v.clamp(0.0, 1.0));
  }
}

/// Small labeled stat used inside analytics cards.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  const StatTile({super.key, required this.label, required this.value, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(Tokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              // Labels like "Longest session" and values like "1h 40m" are
              // sized by the grid, not by their content, so they shrink to fit
              // rather than ellipsising — "Total …" tells the reader nothing.
              Expanded(
                child: FittingText(
                  label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittingText(value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return res ?? false;
}
