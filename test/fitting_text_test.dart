import 'package:everything/core/widgets/fitting_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(TextFitCache.instance.clear);

  double scale(String text, double width, {double minScale = 0.6}) {
    return TextFitCache.instance.scaleFor(
      text: text,
      style: const TextStyle(fontSize: 20),
      maxWidth: width,
      maxHeight: double.infinity,
      maxLines: 1,
      minScale: minScale,
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
  }

  group('fitting', () {
    test('leaves text alone when it already fits', () {
      expect(scale('1h', 400), 1.0);
    });

    test('shrinks text that would otherwise be cut off', () {
      final tight = scale('Longest session today', 60);
      expect(tight, lessThan(1.0));
    });

    test('shrinks further as the space gets tighter', () {
      // Widths chosen to land between the floor and 1.0, where the scale
      // actually varies — the test font lays out each glyph as a fixed box,
      // so this string is about 420px wide at full size.
      const label = 'Longest session today';
      expect(scale(label, 300), lessThan(scale(label, 400)));
      expect(scale(label, 400), lessThan(1.0));
    });

    test('never shrinks past the readable floor', () {
      // Below this the text would be illegible; ellipsis is the better
      // failure, so the scale stops rather than continuing down.
      expect(scale('An extremely long label that cannot fit', 10), 0.6);
      expect(scale('An extremely long label that cannot fit', 10, minScale: 0.8),
          0.8);
    });

    test('an unbounded width never shrinks', () {
      expect(scale('anything at all', double.infinity), 1.0);
    });
  });

  group('cache', () {
    test('reuses a measurement instead of recomputing it', () {
      scale('Total focus', 80);
      expect(TextFitCache.instance.length, 1);

      scale('Total focus', 80);
      expect(TextFitCache.instance.length, 1, reason: 'should have been a hit');
    });

    test('treats a different width as a different question', () {
      scale('Total focus', 80);
      scale('Total focus', 120);
      expect(TextFitCache.instance.length, 2);
    });

    test('treats different text as a different question', () {
      scale('Total focus', 80);
      scale('Total focu', 80);
      expect(TextFitCache.instance.length, 2);
    });

    test('stays bounded so live values cannot grow it forever', () {
      // Stat tiles measure balances and durations, which change constantly —
      // an unbounded cache would leak for the life of the process.
      for (var i = 0; i < TextFitCache.maxEntries + 50; i++) {
        scale('R$i.00', 80);
      }
      expect(TextFitCache.instance.length,
          lessThanOrEqualTo(TextFitCache.maxEntries));
    });
  });

  group('widget', () {
    testWidgets('renders without overflowing its box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 70,
                child: FittingText(
                  'Longest session',
                  style: TextStyle(fontSize: 22),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Longest session'), findsOneWidget);
    });

    testWidgets('re-measures when the available width changes',
        (tester) async {
      Widget boxed(double width) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: const FittingText('Longest session',
                      style: TextStyle(fontSize: 22)),
                ),
              ),
            ),
          );

      await tester.pumpWidget(boxed(70));
      await tester.pump();
      final narrow = TextFitCache.instance.length;

      // A resize is exactly when a re-measure is needed — and the only time.
      await tester.pumpWidget(boxed(200));
      await tester.pump();

      expect(TextFitCache.instance.length, greaterThan(narrow));
      expect(tester.takeException(), isNull);
    });
  });
}
