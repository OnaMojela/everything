import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../settings/app_settings.dart';

/// Result of restoring a backup.
class RestoreReport {
  final int rows;
  final List<String> tables;
  const RestoreReport({required this.rows, required this.tables});
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// Exports and restores everything the app stores.
///
/// Backups are plain JSON so they stay readable and future-proof: a version
/// header, the settings blob, and one array per table.
class BackupService {
  static const formatVersion = 1;

  final AppDatabase db;
  BackupService(this.db);

  /// Every table, in an order that satisfies foreign keys on restore.
  List<TableInfo<Table, dynamic>> get _tablesInDependencyOrder => [
        db.categories,
        db.accounts,
        db.habits,
        db.habitEntries,
        db.tasks,
        db.subtasks,
        db.plannerEvents,
        db.focusSubjects,
        db.focusSessions,
        db.transactions,
        db.budgets,
        db.bills,
        db.goals,
        db.recurringTransactions,
        db.merchantRules,
        db.inboxItems,
      ];

  // -- export ---------------------------------------------------------------

  Future<Map<String, Object?>> buildBackup(AppSettings settings) async {
    final data = <String, Object?>{};
    for (final table in _tablesInDependencyOrder) {
      final rows = await db.customSelect('SELECT * FROM ${table.actualTableName}').get();
      data[table.actualTableName] = rows.map((r) => _encodeRow(r.data)).toList();
    }
    return {
      'format': formatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Everything',
      'settings': settings.toJson(),
      'data': data,
    };
  }

  /// Values arrive as SQLite primitives; only blobs need special handling.
  Map<String, Object?> _encodeRow(Map<String, Object?> row) {
    return row.map((key, value) => MapEntry(
          key,
          value is Uint8List ? base64Encode(value) : value,
        ));
  }

  /// Writes a full backup and asks the user where to keep it. Returns the
  /// saved path, or null when they cancelled.
  Future<String?> exportBackup(AppSettings settings) async {
    final json = const JsonEncoder.withIndent('  ').convert(await buildBackup(settings));
    final bytes = Uint8List.fromList(utf8.encode(json));
    return FilePicker.platform.saveFile(
      dialogTitle: 'Save Everything backup',
      fileName: 'everything-backup-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
  }

  /// Spreadsheet-friendly transaction export.
  Future<String?> exportTransactionsCsv(String currencySymbol) async {
    final txs = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.day)]))
        .get();
    final accounts = {for (final a in await db.select(db.accounts).get()) a.id: a};
    final categories = {for (final c in await db.select(db.categories).get()) c.id: c};

    final buffer = StringBuffer()
      ..writeln('Date,Time,Type,Amount,Currency,Account,To account,Category,'
          'Merchant,Description,Tags,Note');
    for (final t in txs) {
      final type = TxType.values[t.txType];
      buffer.writeln([
        t.day,
        t.time ?? '',
        type.label,
        // Signed decimal, so spreadsheets can sum the column directly.
        (type.sign() * t.amount / 100).toStringAsFixed(2),
        currencySymbol,
        accounts[t.accountId]?.name ?? '',
        t.toAccountId != null ? accounts[t.toAccountId]?.name ?? '' : '',
        categories[t.categoryId]?.name ?? '',
        t.merchant,
        t.description,
        t.tags,
        t.note,
      ].map(_csvCell).join(','));
    }

    return FilePicker.platform.saveFile(
      dialogTitle: 'Export transactions',
      fileName:
          'everything-transactions-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
  }

  static String _csvCell(String value) {
    if (!value.contains(RegExp(r'[",\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  // -- import ---------------------------------------------------------------

  /// Lets the user pick a backup file and restores it, replacing all current
  /// data. Returns null when they cancelled.
  Future<RestoreReport?> importBackup({
    required void Function(AppSettings) applySettings,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose an Everything backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = picked?.files.singleOrNull?.bytes;
    if (bytes == null) return null;

    final Map<String, Object?> parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    } catch (_) {
      throw const BackupException("That file isn't a valid Everything backup.");
    }
    return restoreFrom(parsed, applySettings: applySettings);
  }

  /// Replaces all data with the contents of [backup]. Runs in a transaction,
  /// so a malformed file leaves the existing data untouched.
  Future<RestoreReport> restoreFrom(
    Map<String, Object?> backup, {
    required void Function(AppSettings) applySettings,
  }) async {
    final format = backup['format'];
    final data = backup['data'];
    if (format is! int || data is! Map) {
      throw const BackupException("That file isn't an Everything backup.");
    }
    if (format > formatVersion) {
      throw const BackupException(
          'This backup was made by a newer version of Everything. Update the app first.');
    }

    var rows = 0;
    final restored = <String>[];

    await db.transaction(() async {
      // Delete in reverse dependency order so foreign keys stay satisfied.
      for (final table in _tablesInDependencyOrder.reversed) {
        await db.customStatement('DELETE FROM ${table.actualTableName}');
      }

      for (final table in _tablesInDependencyOrder) {
        final name = table.actualTableName;
        final tableRows = data[name];
        if (tableRows is! List || tableRows.isEmpty) continue;

        final columns = {for (final c in table.$columns) c.name: c};
        for (final row in tableRows) {
          if (row is! Map) continue;
          // Ignore columns the backup has but this version doesn't, so older
          // and newer backups both load.
          final entries = row.entries
              .where((e) => columns.containsKey(e.key))
              .toList();
          if (entries.isEmpty) continue;

          final columnSql = entries.map((e) => '"${e.key}"').join(', ');
          final placeholders = List.filled(entries.length, '?').join(', ');
          final values = [
            for (final e in entries) _decodeValue(columns[e.key]!, e.value)
          ];
          await db.customInsert(
            'INSERT OR REPLACE INTO "$name" ($columnSql) VALUES ($placeholders)',
            variables: values,
          );
          rows++;
        }
        restored.add(name);
      }
    });

    final settingsJson = backup['settings'];
    if (settingsJson is Map) {
      applySettings(AppSettings.fromJson(Map<String, Object?>.from(settingsJson)));
    }

    return RestoreReport(rows: rows, tables: restored);
  }

  Variable<Object> _decodeValue(GeneratedColumn<Object> column, Object? value) {
    if (value == null) return const Variable<Object>(null);
    // JSON has no blob type; those were base64-encoded on the way out.
    if (column.type == DriftSqlType.blob && value is String) {
      return Variable<Uint8List>(base64Decode(value));
    }
    if (column.type == DriftSqlType.bool && value is bool) {
      return Variable<int>(value ? 1 : 0);
    }
    return Variable<Object>(value);
  }
}

final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref.watch(dbProvider)));
