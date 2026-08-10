import 'package:drift/drift.dart';

/// Every table that takes part in cross-device sync, paired with the column
/// that identifies a row. Order matters: parents are listed before the rows
/// that reference them so a pull can insert in this order without tripping
/// foreign keys, and delete in reverse.
///
/// The names here are the SQLite table names, which are also the Postgres
/// table names in Supabase — one vocabulary for both ends of the wire.
const syncedTables = <SyncedTable>[
  SyncedTable('habits', 'id'),
  SyncedTable('tasks', 'id'),
  SyncedTable('planner_events', 'id'),
  SyncedTable('focus_subjects', 'id'),
  SyncedTable('accounts', 'id'),
  SyncedTable('categories', 'id'),
  // Children — these reference the tables above.
  SyncedTable('habit_entries', 'id'),
  SyncedTable('subtasks', 'id'),
  SyncedTable('focus_sessions', 'id'),
  SyncedTable('transactions', 'id'),
  SyncedTable('budgets', 'id'),
  SyncedTable('bills', 'id'),
  SyncedTable('goals', 'id'),
  SyncedTable('recurring_transactions', 'id'),
  SyncedTable('merchant_rules', 'merchant_key'),
  SyncedTable('inbox_items', 'id'),
];

class SyncedTable {
  /// SQLite/Postgres table name.
  final String name;

  /// Column holding the row's identity. Every synced table has a single
  /// text primary key generated on the client, so ids never collide between
  /// devices and no server round-trip is needed to create a row.
  final String key;

  const SyncedTable(this.name, this.key);
}

/// One row per locally-changed record, waiting to be pushed. Repeated edits to
/// the same record collapse onto a single entry, so a busy day of habit ticks
/// still pushes one row per habit rather than one per tap.
class SyncChanges extends Table {
  /// Named `entity` in Dart because Drift's own `Table.tableName` occupies
  /// that name; the SQL column stays `table_name`, which is what the triggers
  /// write to.
  TextColumn get entity => text().named('table_name')();
  TextColumn get rowId => text()();

  /// `'upsert'` or `'delete'`.
  TextColumn get op => text()();

  /// Local clock, milliseconds since epoch. Used for ordering and for showing
  /// "unsynced since…", never for conflict resolution — the server's clock
  /// decides that.
  IntColumn get changedAt => integer()();

  @override
  Set<Column> get primaryKey => {entity, rowId};
}

/// Small key/value store for sync bookkeeping: the pull cursor per table, the
/// signed-in user id, and the last successful sync time.
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

abstract final class SyncKeys {
  /// Supabase user id the local database currently belongs to. A different id
  /// signing in means the local data is someone else's and gets wiped.
  static const ownerUserId = 'owner_user_id';

  /// ISO-8601 timestamp of the last sync that completed without error.
  static const lastSyncedAt = 'last_synced_at';

  /// Pull cursor for [table] — the newest `sync_updated_at` we have applied.
  static String cursor(String table) => 'cursor:$table';
}

/// While this flag is set, the change-log triggers stay quiet. It is held for
/// the duration of a pull so that rows arriving from the server are not
/// immediately queued to be pushed straight back.
const _suppressKey = 'suppress_change_log';

/// SQL that records inserts, updates and deletes into `sync_changes`.
///
/// Triggers rather than Dart code, for two reasons: existing repository and
/// UI code needs no changes at all, and SQLite fires delete triggers for rows
/// removed by `ON DELETE CASCADE` — so deleting a habit correctly tombstones
/// its entries, which application-level tracking would quietly miss.
List<String> changeLogTriggers() {
  final statements = <String>[];

  // These triggers write only to `sync_changes`, which has no triggers of its
  // own, so they cannot re-enter even though the database runs with
  // `recursive_triggers = ON` (which it must, for cascade deletes to be seen).
  const notSuppressed =
      "(SELECT COUNT(*) FROM sync_state WHERE key = '$_suppressKey') = 0";

  for (final t in syncedTables) {
    for (final (event, id, op) in [
      ('INSERT', 'NEW', 'upsert'),
      ('UPDATE', 'NEW', 'upsert'),
      ('DELETE', 'OLD', 'delete'),
    ]) {
      statements.add('''
CREATE TRIGGER IF NOT EXISTS sync_log_${t.name}_${event.toLowerCase()}
AFTER $event ON ${t.name}
WHEN $notSuppressed
BEGIN
  INSERT INTO sync_changes (table_name, row_id, op, changed_at)
  VALUES ('${t.name}', $id.${t.key}, '$op', CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER))
  ON CONFLICT(table_name, row_id) DO UPDATE SET
    op = excluded.op,
    changed_at = excluded.changed_at;
END;''');
    }
  }
  return statements;
}

/// Statements that remove every change-log trigger, used before a bulk local
/// wipe so the wipe itself is not queued for push.
List<String> dropChangeLogTriggers() => [
      for (final t in syncedTables)
        for (final event in ['insert', 'update', 'delete'])
          'DROP TRIGGER IF EXISTS sync_log_${t.name}_$event;',
    ];

/// Marker rows that turn the change log off and back on.
const suppressChangeLogSql =
    "INSERT OR REPLACE INTO sync_state (key, value) VALUES ('$_suppressKey', '1')";
const resumeChangeLogSql =
    "DELETE FROM sync_state WHERE key = '$_suppressKey'";
