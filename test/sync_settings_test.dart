import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/providers.dart';
import 'package:everything/data/sync/sync_providers.dart';
import 'package:everything/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The settings screen has to stay usable in a build with no backend, because
/// that is exactly what an offline-only or misconfigured deploy produces.
void main() {
  late AppDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsScreen()),
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

  testWidgets('hides the sync section when no backend is configured',
      (tester) async {
    await pumpSettings(tester);

    expect(tester.takeException(), isNull);
    // Showing a sign-in button that cannot work is worse than showing nothing.
    expect(find.text('Sync'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
    // The rest of settings still renders.
    expect(find.text('Appearance'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('offers sign-in when a backend is configured', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          // Stand in for a configured project without reaching the network.
          syncAvailableProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Sync'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Continue with Google'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Continue with Google'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('describes storage honestly while signed out', (tester) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(
      find.textContaining('never sent anywhere'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('No account'), findsOneWidget);

    await unmount(tester);
  });
}
