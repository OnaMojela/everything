import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:everything/core/services/backup_service.dart';
import 'package:everything/core/settings/app_settings.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BackupService service;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BackupService(db);
  });

  tearDown(() async => db.close());

  Future<void> seed() async {
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1',
          name: 'Cheque',
          accountType: AccountType.checking.index,
          colorValue: 0xFF0B84FF,
          initialBalance: const Value(150000),
          notificationHints: const Value('1234,nedbank'),
        ));
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat_custom',
          name: 'Coffee',
          iconCode: 0xe1a1,
          colorValue: 0xFFDB8B00,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          txType: TxType.expense.index,
          amount: 4599,
          accountId: 'acc1',
          categoryId: const Value('cat_custom'),
          merchant: const Value('Bean There'),
          description: const Value('Flat white, "large"'),
          day: '2026-08-03',
          createdAt: DateTime(2026, 8, 3, 9),
        ));
    await db.into(db.habits).insert(HabitsCompanion.insert(
          id: 'h1',
          title: 'Read',
          iconCode: 0xe1a2,
          colorValue: 0xFF2E9E5B,
          habitType: HabitType.numeric.index,
          scheduleType: ScheduleType.daily.index,
          anchorDate: '2026-08-01',
          targetValue: const Value(20),
          archived: const Value(false),
          createdAt: DateTime(2026, 8, 1),
        ));
    await db.into(db.habitEntries).insert(HabitEntriesCompanion.insert(
          id: 'h1_2026-08-02',
          habitId: 'h1',
          day: '2026-08-02',
          value: const Value(25),
          completed: const Value(true),
        ));
  }

  test('backup captures every table and the settings', () async {
    await seed();
    const settings = AppSettings(userName: 'Onale', currencySymbol: 'R');

    final backup = await service.buildBackup(settings);
    final data = backup['data'] as Map<String, Object?>;

    expect(backup['format'], BackupService.formatVersion);
    expect(backup['schemaVersion'], db.schemaVersion);
    expect((backup['settings'] as Map)['userName'], 'Onale');
    expect((data['accounts'] as List), hasLength(1));
    expect((data['transactions'] as List), hasLength(1));
    expect((data['habits'] as List), hasLength(1));
    expect((data['habit_entries'] as List), hasLength(1));
    // Seeded default categories plus the custom one.
    expect((data['categories'] as List).length, greaterThan(1));
  });

  test('restoring into an empty database reproduces the data exactly',
      () async {
    await seed();
    final backup = await service.buildBackup(const AppSettings());

    // Round-trip through JSON, as a real file would.
    final wire = jsonDecode(jsonEncode(backup)) as Map<String, Object?>;

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final report =
        await BackupService(fresh).restoreFrom(wire, applySettings: (_) {});

    expect(report.rows, greaterThan(4));

    final account = await (fresh.select(fresh.accounts)
          ..where((a) => a.id.equals('acc1')))
        .getSingle();
    expect(account.name, 'Cheque');
    expect(account.initialBalance, 150000); // cents preserved
    expect(account.notificationHints, '1234,nedbank');

    final tx = await (fresh.select(fresh.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(tx.amount, 4599);
    expect(tx.description, 'Flat white, "large"'); // quotes survive
    expect(tx.categoryId, 'cat_custom');

    final entry = await fresh.select(fresh.habitEntries).getSingle();
    expect(entry.completed, isTrue);
    expect(entry.value, 25);
  });

  test('restoring replaces existing data rather than merging it', () async {
    await seed();
    final backup = await service.buildBackup(const AppSettings());

    // A second database with different data that must not survive.
    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    await other.into(other.accounts).insert(AccountsCompanion.insert(
          id: 'stale',
          name: 'Old account',
          accountType: 0,
          colorValue: 0,
        ));

    await BackupService(other).restoreFrom(backup, applySettings: (_) {});

    final accounts = await other.select(other.accounts).get();
    expect(accounts.map((a) => a.id), ['acc1']);
  });

  test('settings come back with the data', () async {
    await seed();
    final backup = await service.buildBackup(
        const AppSettings(userName: 'Onale', currencySymbol: '£', accentIndex: 3));

    AppSettings? applied;
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await BackupService(fresh)
        .restoreFrom(backup, applySettings: (s) => applied = s);

    expect(applied?.userName, 'Onale');
    expect(applied?.currencySymbol, '£');
    expect(applied?.accentIndex, 3);
  });

  test('a backup from a future version is refused', () async {
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    expect(
      () => BackupService(fresh).restoreFrom(
        {'format': BackupService.formatVersion + 1, 'data': const {}},
        applySettings: (_) {},
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test('a file that is not a backup is refused', () async {
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    expect(
      () => BackupService(fresh)
          .restoreFrom({'hello': 'world'}, applySettings: (_) {}),
      throwsA(isA<BackupException>()),
    );
  });

  test('unknown columns in a backup are ignored rather than failing', () async {
    await seed();
    final backup = await service.buildBackup(const AppSettings());
    final data = backup['data'] as Map<String, Object?>;
    // Pretend a newer version added a column.
    for (final row in (data['accounts'] as List).cast<Map<String, Object?>>()) {
      row['some_future_column'] = 'ignore me';
    }

    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    await BackupService(fresh).restoreFrom(backup, applySettings: (_) {});

    expect((await fresh.select(fresh.accounts).get()).single.name, 'Cheque');
  });
}
