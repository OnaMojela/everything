import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:everything/app.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overflow is reported as a painting exception rather than a failure, so it
/// is invisible to a test that only checks widgets exist. These sizes are the
/// ones that actually overflowed on a device: a narrow phone, and a phone in
/// landscape where the navigation rail runs out of height.
void main() {
  late AppDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const EverythingApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// Fails on any RenderFlex overflow, which Flutter otherwise only draws as
  /// the yellow-and-black stripes.
  void expectNoOverflow(WidgetTester tester, String where) {
    final error = tester.takeException();
    expect(
      error,
      isNull,
      reason: 'overflow or paint error at $where: $error',
    );
  }

  testWidgets('narrow phone lays out without overflow', (tester) async {
    await pumpAt(tester, const Size(360, 740));
    expectNoOverflow(tester, '360x740 portrait');
    await unmount(tester);
  });

  testWidgets('very narrow phone lays out without overflow', (tester) async {
    await pumpAt(tester, const Size(320, 640));
    expectNoOverflow(tester, '320x640 portrait');
    await unmount(tester);
  });

  // The navigation rail appears above 700px wide, and this is where it ran out
  // of vertical room for its logo, destinations and trailing buttons.
  testWidgets('phone in landscape keeps the rail within its height',
      (tester) async {
    await pumpAt(tester, const Size(880, 400));
    expectNoOverflow(tester, '880x400 landscape');
    await unmount(tester);
  });

  testWidgets('short desktop window keeps the rail within its height',
      (tester) async {
    await pumpAt(tester, const Size(1280, 360));
    expectNoOverflow(tester, '1280x360');
    await unmount(tester);
  });

  testWidgets('wide desktop lays out without overflow', (tester) async {
    await pumpAt(tester, const Size(1920, 1080));
    expectNoOverflow(tester, '1920x1080');
    await unmount(tester);
  });

  // Pushed routes cap their content width for readability, which on a wide
  // window used to leave the margins either side unpainted — they showed
  // through to whatever was underneath, so Settings looked unlike every screen
  // reached from the rail.
  testWidgets('pushed routes paint the full width on a wide window',
      (tester) async {
    await pumpAt(tester, const Size(1600, 900));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Appearance'), findsOneWidget,
        reason: 'should be on the settings route');

    final context = tester.element(find.text('Appearance'));
    final background = Theme.of(context).scaffoldBackgroundColor;

    final filled = find
        .byWidgetPredicate((w) => w is ColoredBox && w.color == background)
        .evaluate()
        .map((e) => e.renderObject! as RenderBox)
        .where((box) => box.size.width == 1600);

    expect(filled, isNotEmpty,
        reason: 'the scaffold background should span the whole viewport, not '
            'just the capped content column');

    expectNoOverflow(tester, 'settings at 1600x900');
    await unmount(tester);
  });

  // The Focus tab's Discard/Finish pair — the other reported overflow — is
  // not covered here. Reaching it needs a running session, which needs a
  // seeded subject and a timer, and driving that through the tab bar proved
  // brittle enough to be worse than no test. That row is now two Expanded
  // children, which share the available width and cannot overflow it by
  // construction, so there is nothing left for a size-based test to catch.
}
