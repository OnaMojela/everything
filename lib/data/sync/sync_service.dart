import 'dart:async';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
import 'row_codec.dart';

/// How far back to re-read on each pull. Postgres timestamps have microsecond
/// resolution, so two rows written in the same instant can straddle the
/// cursor; overlapping slightly and relying on idempotent upserts is cheaper
/// and safer than trying to make the cursor exact.
const _cursorOverlap = Duration(seconds: 1);

/// Rows per request. Large enough that a first upload of a few thousand rows
/// is a handful of round trips, small enough to stay well inside PostgREST's
/// payload limits.
const _pageSize = 500;

enum SyncStage { idle, pushing, pulling }

class SyncStatus {
  final SyncStage stage;
  final DateTime? lastSyncedAt;
  final int pendingChanges;
  final Object? error;

  const SyncStatus({
    this.stage = SyncStage.idle,
    this.lastSyncedAt,
    this.pendingChanges = 0,
    this.error,
  });

  bool get isSyncing => stage != SyncStage.idle;

  SyncStatus copyWith({
    SyncStage? stage,
    DateTime? lastSyncedAt,
    int? pendingChanges,
    Object? error,
    bool clearError = false,
  }) =>
      SyncStatus(
        stage: stage ?? this.stage,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        pendingChanges: pendingChanges ?? this.pendingChanges,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Two-way sync between the local Drift database and Supabase.
///
/// The local database stays the source of truth: the UI only ever reads
/// SQLite, so the app behaves identically offline and the sync engine can fail
/// without taking any feature down with it.
///
/// A cycle is always **push, then pull**. That ordering is what makes conflict
/// handling honest — by the time the pull runs, this device's own pending
/// edits are already on the server, so a row coming back can be applied
/// without the risk of overwriting a local change that had not been sent yet.
/// Where two devices really did edit the same row, the later write wins,
/// judged by the server's clock rather than either device's.
class SyncService {
  final AppDatabase db;
  final SupabaseClient supabase;
  final RowCodec _codec;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();

  /// Serialises cycles: a manual tap during an automatic sync joins the run in
  /// progress instead of starting a second one against the same tables.
  Future<void>? _inFlight;

  SyncService({required this.db, required this.supabase})
      : _codec = RowCodec(db);

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get status => _status;

  void _emit(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  Future<void> dispose() => _statusController.close();

  String? get _userId => supabase.auth.currentUser?.id;

  // -- entry points ---------------------------------------------------------

  /// Runs one full cycle. Concurrent calls share a single run.
  Future<void> sync() {
    final running = _inFlight;
    if (running != null) return running;
    final run = _run().whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<void> _run() async {
    final userId = _userId;
    if (userId == null) return;

    _emit(_status.copyWith(stage: SyncStage.pushing, clearError: true));
    try {
      await _push(userId);
      _emit(_status.copyWith(stage: SyncStage.pulling));
      await _pull(userId);

      final now = DateTime.now();
      await _writeState(SyncKeys.lastSyncedAt, now.toIso8601String());
      _emit(SyncStatus(
        lastSyncedAt: now,
        pendingChanges: await pendingCount(),
      ));
    } catch (e) {
      _emit(_status.copyWith(
        stage: SyncStage.idle,
        error: e,
        pendingChanges: await pendingCount(),
      ));
      rethrow;
    }
  }

  /// Prepares the local database for [userId].
  ///
  /// If it already holds another account's data it is wiped first — sync
  /// should never blend two people's finances because they shared a laptop.
  /// A database that has never synced keeps its rows and queues all of them,
  /// so signing in for the first time uploads the work already done offline
  /// rather than discarding it.
  Future<void> adoptUser(String userId) async {
    final owner = await _readState(SyncKeys.ownerUserId);
    if (owner == userId) return;

    if (owner == null) {
      await queueEverythingForUpload();
    } else {
      await db.wipeLocalData();
    }
    await _writeState(SyncKeys.ownerUserId, userId);
    _emit(_status.copyWith(pendingChanges: await pendingCount()));
  }

  /// Marks every local row as needing upload. Used on first sign-in.
  Future<void> queueEverythingForUpload() async {
    for (final table in syncedTables) {
      await db.customStatement('''
INSERT INTO sync_changes (table_name, row_id, op, changed_at)
SELECT '${table.name}', ${table.key}, 'upsert',
       CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
FROM ${table.name}
ON CONFLICT(table_name, row_id) DO NOTHING;''');
    }
  }

  /// Clears the pull cursors so the next sync re-reads everything from the
  /// server. Local rows are untouched; upserts make the replay harmless.
  Future<void> resetCursors() async {
    await (db.delete(db.syncState)
          ..where((s) => s.key.like('cursor:%')))
        .go();
  }

  Future<int> pendingCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_changes')
        .getSingle();
    return row.read<int>('c');
  }

  /// Live count of unsynced local edits, for the settings screen.
  Stream<int> watchPendingCount() => db
      .customSelect(
        'SELECT COUNT(*) AS c FROM sync_changes',
        readsFrom: {db.syncChanges},
      )
      .map((row) => row.read<int>('c'))
      .watchSingle();

  Future<void> loadPersistedStatus() async {
    final raw = await _readState(SyncKeys.lastSyncedAt);
    _emit(_status.copyWith(
      lastSyncedAt: raw == null ? null : DateTime.tryParse(raw),
      pendingChanges: await pendingCount(),
    ));
  }

  // -- push -----------------------------------------------------------------

  /// Sends queued local edits, parents before children.
  Future<void> _push(String userId) async {
    for (final table in syncedTables) {
      final changes = await (db.select(db.syncChanges)
            ..where((c) => c.entity.equals(table.name)))
          .get();
      if (changes.isEmpty) continue;

      final deletes = changes.where((c) => c.op == 'delete').toList();
      final upserts = changes.where((c) => c.op == 'upsert').toList();

      if (upserts.isNotEmpty) await _pushUpserts(userId, table, upserts);
      if (deletes.isNotEmpty) await _pushDeletes(userId, table, deletes);
    }
  }

  Future<void> _pushUpserts(
    String userId,
    SyncedTable table,
    List<SyncChange> changes,
  ) async {
    for (final batch in _batches(changes)) {
      final ids = batch.map((c) => c.rowId).toList();
      final rows = await db
          .customSelect(
            'SELECT * FROM ${table.name} '
            'WHERE ${table.key} IN (${_placeholders(ids.length)})',
            variables: ids.map(Variable<String>.new).toList(),
          )
          .get();

      final found = {
        for (final row in rows) row.data[table.key] as String: row.data,
      };

      final payload = [
        for (final row in rows)
          {..._codec.toRemote(table.name, row.data), 'user_id': userId},
      ];
      if (payload.isNotEmpty) {
        await supabase
            .from(table.name)
            .upsert(payload, onConflict: 'user_id,${table.key}');
      }

      // A row queued for upsert that no longer exists was deleted while the
      // push was being prepared. Its delete is already queued as a separate
      // change, so leaving that entry alone lets the delete take over.
      final missing = ids.where((id) => !found.containsKey(id)).toSet();
      await _clearChanges(batch, skip: missing);
    }
  }

  Future<void> _pushDeletes(
    String userId,
    SyncedTable table,
    List<SyncChange> changes,
  ) async {
    for (final batch in _batches(changes)) {
      final ids = batch.map((c) => c.rowId).toList();
      // Tombstones rather than real deletes: a removed row has to stay
      // visible long enough for every other device to notice it is gone.
      await supabase
          .from(table.name)
          .update({'sync_deleted': true})
          .eq('user_id', userId)
          .inFilter(table.key, ids);
      await _clearChanges(batch);
    }
  }

  /// Removes queued changes that have now been sent.
  ///
  /// Each entry is cleared only if its `changed_at` still matches what was
  /// read at the start of the request. An edit made while the network call
  /// was in flight moves that timestamp forward, and its queue entry survives
  /// to be picked up by the next cycle instead of being silently dropped.
  Future<void> _clearChanges(
    List<SyncChange> sent, {
    Set<String> skip = const {},
  }) async {
    for (final change in sent) {
      if (skip.contains(change.rowId)) continue;
      await (db.delete(db.syncChanges)
            ..where((c) =>
                c.entity.equals(change.entity) &
                c.rowId.equals(change.rowId) &
                c.changedAt.equals(change.changedAt)))
          .go();
    }
  }

  // -- pull -----------------------------------------------------------------

  /// Applies server changes, parents before children so local foreign keys
  /// always have something to point at.
  ///
  /// Asks the server once which tables have anything new before querying any
  /// of them. Polling often enough to feel live is only affordable because an
  /// idle cycle costs a single request rather than one per table.
  Future<void> _pull(String userId) async {
    final changed = await _changedTables();
    for (final table in syncedTables) {
      if (changed != null && !changed.contains(table.name)) continue;
      await _pullTable(userId, table);
    }
  }

  /// Table names with rows newer than the oldest cursor we hold, or null if
  /// the server could not answer — in which case the caller falls back to
  /// checking every table, so a project that has not run the latest migration
  /// still syncs correctly, just less efficiently.
  Future<Set<String>?> _changedTables() async {
    // The oldest cursor is the only safe question to ask: a table with nothing
    // newer than that cannot have anything newer than its own cursor, which is
    // at least as recent.
    var oldest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    var first = true;
    for (final table in syncedTables) {
      final raw = await _readState(SyncKeys.cursor(table.name));
      final cursor = raw == null ? null : DateTime.tryParse(raw);
      if (cursor == null) return null; // Never pulled — check everything.
      if (first || cursor.isBefore(oldest)) {
        oldest = cursor;
        first = false;
      }
    }

    try {
      final rows = await supabase.rpc(
        'sync_changed_tables',
        params: {
          'since': oldest.subtract(_cursorOverlap).toUtc().toIso8601String(),
        },
      );
      return {
        for (final row in (rows as List).cast<Map<String, dynamic>>())
          row['table_name'] as String,
      };
    } on PostgrestException {
      // Function missing (migration not applied yet) or not callable.
      return null;
    }
  }

  Future<void> _pullTable(String userId, SyncedTable table) async {
    final cursorKey = SyncKeys.cursor(table.name);
    final since = DateTime.tryParse(await _readState(cursorKey) ?? '')
            ?.subtract(_cursorOverlap) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    var from = since;
    while (true) {
      final rows = await supabase
          .from(table.name)
          .select()
          .eq('user_id', userId)
          .gte('sync_updated_at', from.toUtc().toIso8601String())
          .order('sync_updated_at')
          .limit(_pageSize);

      final page = (rows as List).cast<Map<String, dynamic>>();
      if (page.isEmpty) break;

      await _apply(table, page);

      final newest = DateTime.parse(page.last['sync_updated_at'] as String);
      await _writeState(cursorKey, newest.toIso8601String());

      if (page.length < _pageSize) break;
      if (!newest.isAfter(from)) {
        // A full page sharing one timestamp cannot be paged past by time
        // alone. Nudging forward risks skipping rows, so stop and let the
        // next cycle continue from here rather than lose data.
        break;
      }
      from = newest;
    }
  }

  Future<void> _apply(SyncedTable table, List<Map<String, dynamic>> page) async {
    // Rows edited locally since the last push are left alone: the local copy
    // is newer than anything this pull can be carrying, and it is already
    // queued to go out on the next cycle.
    final pending = await (db.select(db.syncChanges)
          ..where((c) => c.entity.equals(table.name)))
        .get();
    final pendingIds = pending.map((c) => c.rowId).toSet();

    final incoming = page
        .where((row) => !pendingIds.contains(row[table.key] as String))
        .toList();
    if (incoming.isEmpty) return;

    await db.withoutChangeLog(() async {
      await db.transaction(() async {
        for (final row in incoming) {
          final id = row[table.key] as String;
          if (row['sync_deleted'] == true) {
            await db.customStatement(
              'DELETE FROM ${table.name} WHERE ${table.key} = ?',
              [id],
            );
            continue;
          }
          final values = _codec.fromRemote(table.name, row);
          final columns = values.keys.toList();
          // Deliberately not `INSERT OR REPLACE`: that deletes the existing
          // row before reinserting it, which fires `ON DELETE CASCADE` and
          // would take a habit's entries — or an account's transactions —
          // down with what is only meant to be an update.
          final assignments = columns
              .where((c) => c != table.key)
              .map((c) => '$c = excluded.$c')
              .join(', ');
          await db.customStatement(
            'INSERT INTO ${table.name} (${columns.join(', ')}) '
            'VALUES (${_placeholders(columns.length)}) '
            'ON CONFLICT(${table.key}) DO UPDATE SET $assignments',
            columns.map((c) => values[c]).toList(),
          );
        }
      });
    });
  }

  // -- helpers --------------------------------------------------------------

  Iterable<List<T>> _batches<T>(List<T> items) sync* {
    for (var i = 0; i < items.length; i += _pageSize) {
      yield items.sublist(i, (i + _pageSize).clamp(0, items.length));
    }
  }

  String _placeholders(int count) => List.filled(count, '?').join(', ');

  Future<String?> _readState(String key) async {
    final row = await (db.select(db.syncState)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeState(String key, String value) => db
      .into(db.syncState)
      .insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));
}
