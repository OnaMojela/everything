// Generates every app icon from one definition, so the web, PWA and Android
// icons cannot drift apart.
//
//   flutter test tool/generate_icons.dart
//
// Rendered with Flutter's own canvas rather than an image tool, because the
// project already depends on Flutter and nothing else is guaranteed to be
// installed. The mark is drawn as a path, not a font glyph — a text-rendered
// infinity would depend on whatever font happened to be available and would
// hint differently at small sizes.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Indigo — the app's default accent, and the colour the web boot screen
/// already uses, so the icon and first paint agree.
const _brand = Color(0xFF5B5BD6);
const _mark = Colors.white;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate app icons', () async {
    // Web / PWA. Maskable variants are full-bleed: the launcher applies its
    // own mask, so drawing rounded corners would leave clipped corners inside
    // the mask on some devices.
    await _write('web/icons/Icon-192.png', 192, rounded: true);
    await _write('web/icons/Icon-512.png', 512, rounded: true);
    await _write('web/icons/Icon-maskable-192.png', 192, maskable: true);
    await _write('web/icons/Icon-maskable-512.png', 512, maskable: true);
    await _write('web/favicon.png', 64, rounded: true);

    // Android launcher icons, one per density bucket.
    const densities = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final MapEntry(key: bucket, value: size) in densities.entries) {
      await _write(
        'android/app/src/main/res/mipmap-$bucket/ic_launcher.png',
        size,
        rounded: true,
      );
    }
  });
}

Future<void> _write(
  String path,
  int size, {
  bool rounded = false,
  bool maskable = false,
}) async {
  final bytes = await _render(size, rounded: rounded, maskable: maskable);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('wrote $path (${size}x$size, ${bytes.length} bytes)');
}

Future<Uint8List> _render(
  int size, {
  required bool rounded,
  required bool maskable,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();
  final bg = Paint()..color = _brand;

  if (maskable) {
    canvas.drawRect(Rect.fromLTWH(0, 0, s, s), bg);
  } else if (rounded) {
    // Roughly the squircle radius Android and iOS use for legacy icons.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)),
      bg,
    );
  } else {
    canvas.drawRect(Rect.fromLTWH(0, 0, s, s), bg);
  }

  // Maskable icons must keep their content inside the middle 80% — anything
  // outside can be cropped away by the launcher's mask.
  final markWidth = s * (maskable ? 0.46 : 0.62);

  canvas.save();
  canvas.translate(s / 2, s / 2);
  canvas.drawPath(
    _infinity(markWidth),
    Paint()
      ..color = _mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = markWidth * 0.135
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true,
  );
  canvas.restore();

  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A lemniscate of Bernoulli, centred on the origin:
///
///     x = cos t / (1 + sin²t)
///     y = sin t · cos t / (1 + sin²t)
///
/// Chosen over the simpler lemniscate of Gerono (`y = sin t · cos t`), which
/// has cusps at its outer ends and reads as a bowtie once stroked. Bernoulli
/// puts its only sharp point at the crossing, where a stroke hides it, and
/// leaves the two lobes round — which is what makes it look like an infinity
/// sign. Symmetric on both axes, so the mark is optically centred without
/// nudging.
Path _infinity(double width) {
  const steps = 360;
  // The curve is naturally rather flat; a little vertical gain gives the
  // lobes enough weight to read at 48px without thickening the stroke.
  const verticalGain = 1.35;

  final path = Path();
  final a = width / 2;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps * 2 * math.pi;
    final denominator = 1 + math.pow(math.sin(t), 2);
    final x = a * math.cos(t) / denominator;
    final y = a * math.sin(t) * math.cos(t) / denominator * verticalGain;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path..close();
}
