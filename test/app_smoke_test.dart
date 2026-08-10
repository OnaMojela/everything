import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:everything/app.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the real app against an in-memory database at phone and desktop
/// sizes — guards the responsive shell and routing used by the web build.
void main() {
  late AppDatabase db;

  setUpAll(() {
    // Each test builds its own database on purpose.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const EverythingApp(),
      ),
    );
    // Bounded settle: drift's query streams keep emitting, so pumpAndSettle
    // can spin forever.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Unmounts the tree and drains the zero-duration timers drift schedules
  /// when its stream subscriptions are disposed.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('phone layout uses bottom navigation', (tester) async {
    await pumpApp(tester, const Size(400, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await unmount(tester);
  });

  testWidgets('desktop layout uses a side rail with branding', (tester) async {
    await pumpApp(tester, const Size(1400, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Everything'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('navigates across modules without exceptions', (tester) async {
    await pumpApp(tester, const Size(1400, 900));

    for (final label in ['Productivity', 'Finance', 'Analytics', 'Home']) {
      await tester.tap(find.text(label).last);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(tester.takeException(), isNull, reason: 'failed opening $label');
    }

    await unmount(tester);
  });

  test('fresh database seeds finance categories', () async {
    final categories = await db.select(db.categories).get();
    expect(categories, isNotEmpty);
    expect(categories.where((c) => c.isIncome), isNotEmpty);
    expect(categories.where((c) => !c.isIncome), isNotEmpty);
  });
}
