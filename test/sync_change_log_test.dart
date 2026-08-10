import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:everything/core/utils/utils.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/models/enums.dart';
import 'package:everything/data/sync/row_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Force the database open so `beforeOpen` installs the triggers.
    await db.customSelect('SELECT 1').get();
    // The seeded default categories are queued by nothing — start from a
    // clean slate so each test's assertions are about its own writes.
    await db.delete(db.syncChanges).go();
  });

  tearDown(() => db.close());

  Future<List<SyncChange>> pending([String? table]) {
    final q = db.select(db.syncChanges);
    if (table != null) q.where((c) => c.entity.equals(table));
    return q.get();
  }

  Future<Habit> insertHabit({String id = 'h1'}) async {
    await db.into(db.habits).insert(HabitsCompanion.insert(
          id: id,
          title: 'Read',
          iconCode: 1,
          colorValue: 2,
          habitType: HabitType.check.index,
          scheduleType: ScheduleType.daily.index,
          anchorDate: dayKey(today),
          createdAt: DateTime.now(),
        ));
    return (db.select(db.habits)..where((h) => h.id.equals(id))).getSingle();
  }

  group('change log', () {
    test('records an insert as an upsert', () async {
      await insertHabit();

      final changes = await pending('habits');
      expect(changes, hasLength(1));
      expect(changes.single.rowId, 'h1');
      expect(changes.single.op, 'upsert');
    });

    test('collapses repeated edits to one entry', () async {
      final habit = await insertHabit();
      for (var i = 0; i < 5; i++) {
        await (db.update(db.habits)..where((h) => h.id.equals(habit.id)))
            .write(HabitsCompanion(sortOrder: Value(i)));
      }

      expect(await pending('habits'), hasLength(1));
    });

    test('a delete supersedes a queued upsert', () async {
      await insertHabit();
      await (db.delete(db.habits)..where((h) => h.id.equals('h1'))).go();

      final changes = await pending('habits');
      expect(changes, hasLength(1));
      expect(changes.single.op, 'delete');
    });

    test('every row of a multi-row delete is tombstoned', () async {
      final habit = await insertHabit();
      for (final day in ['2026-01-01', '2026-01-02', '2026-01-03']) {
        await db.into(db.habitEntries).insert(HabitEntriesCompanion.insert(
              id: 'e_$day',
              habitId: habit.id,
              day: day,
            ));
      }
      await db.delete(db.syncChanges).go();

      await (db.delete(db.habitEntries)..where((e) => e.habitId.equals('h1')))
          .go();

      final changes = await pending('habit_entries');
      expect(changes, hasLength(3));
      expect(changes.every((c) => c.op == 'delete'), isTrue);
    });

    // Pins current behaviour rather than endorsing it. The schema declares
    // `onDelete: KeyAction.cascade` on several tables, but drift_dev could not
    // resolve those `references()` calls and emitted no foreign keys at all —
    // so deleting a habit leaves its entries behind, here and in the shipped
    // app. Sync stays consistent either way (the orphans simply exist on every
    // device), and the change-log triggers already handle real cascades, so
    // fixing the schema will not require touching the sync engine. This test
    // will fail when that happens, which is the point.
    test('deleting a habit does not currently remove its entries', () async {
      final habit = await insertHabit();
      await db.into(db.habitEntries).insert(HabitEntriesCompanion.insert(
            id: 'e1',
            habitId: habit.id,
            day: dayKey(today),
          ));
      await db.delete(db.syncChanges).go();

      await (db.delete(db.habits)..where((h) => h.id.equals(habit.id))).go();

      expect(await db.select(db.habitEntries).get(), hasLength(1));
      expect(await pending('habit_entries'), isEmpty);
    });

    test('withoutChangeLog leaves nothing queued', () async {
      await db.withoutChangeLog(() => insertHabit());

      expect(await pending(), isEmpty);
    });

    test('the log resumes after withoutChangeLog', () async {
      await db.withoutChangeLog(() => insertHabit(id: 'quiet'));
      await insertHabit(id: 'loud');

      final changes = await pending('habits');
      expect(changes.map((c) => c.rowId), ['loud']);
    });

    test('a wipe clears data without queuing the deletions', () async {
      await insertHabit();
      await db.wipeLocalData();

      expect(await db.select(db.habits).get(), isEmpty);
      expect(await pending(), isEmpty);
      // Defaults come back so the app is usable immediately after signing out.
      expect(await db.select(db.categories).get(), isNotEmpty);
    });

    test('the log still works after a wipe', () async {
      await db.wipeLocalData();
      await insertHabit();

      expect(await pending('habits'), hasLength(1));
    });
  });

  group('row codec', () {
    test('maps SQLite 0/1 to Postgres booleans and back', () {
      final codec = RowCodec(db);
      final row = {'id': 'h1', 'archived': 0, 'sort_order': 3};

      final remote = codec.toRemote('habits', row);
      expect(remote['archived'], isFalse);
      expect(remote['sort_order'], 3);

      final local = codec.fromRemote('habits', {...remote, 'archived': true});
      expect(local['archived'], 1);
    });

    test('drops columns the local schema does not have', () {
      final codec = RowCodec(db);

      final local = codec.fromRemote('habits', {
        'id': 'h1',
        'user_id': 'abc',
        'sync_updated_at': '2026-01-01T00:00:00Z',
        'sync_deleted': false,
        'a_column_from_a_newer_build': 1,
      });

      expect(local.keys, ['id']);
    });

    test('widens integers into real columns', () {
      final codec = RowCodec(db);

      final local = codec.fromRemote('habits', {'target_value': 3});

      expect(local['target_value'], 3.0);
      expect(local['target_value'], isA<double>());
    });
  });
}
