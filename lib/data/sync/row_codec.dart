import 'package:drift/drift.dart';

/// Translates rows between SQLite's storage representation and the JSON that
/// PostgREST expects.
///
/// The only real difference is booleans: SQLite keeps them as 0/1 integers,
/// Postgres wants `true`/`false`. Everything else — text, integers, reals, and
/// datetimes (which Drift stores as unix seconds) — passes through untouched.
///
/// The conversion is driven by Drift's own column metadata rather than a
/// hand-written table, so adding a column to the schema needs no change here.
class RowCodec {
  /// `tableName -> columnName -> type`, built once from the live schema.
  /// Columns with a custom type are skipped — the schema has none, and
  /// silently guessing at one would be worse than leaving it out.
  final Map<String, Map<String, DriftSqlType>> _types;

  RowCodec(GeneratedDatabase db)
      : _types = {
          for (final table in db.allTables)
            table.actualTableName: {
              for (final column in table.$columns)
                if (column.type case final DriftSqlType type)
                  column.name: type,
            },
        };

  Set<String> columnsOf(String table) => _types[table]?.keys.toSet() ?? const {};

  /// SQLite row -> JSON body for Supabase.
  Map<String, Object?> toRemote(String table, Map<String, Object?> row) {
    final types = _types[table]!;
    return {
      for (final entry in row.entries)
        if (types.containsKey(entry.key))
          entry.key: types[entry.key] == DriftSqlType.bool && entry.value is int
              ? entry.value != 0
              : entry.value,
    };
  }

  /// Supabase row -> values ready to bind into a SQLite insert. Columns the
  /// local schema does not know about (the server's own sync bookkeeping, or
  /// a column added by a newer build) are dropped rather than causing a
  /// failure, so an older client stays usable against a newer database.
  Map<String, Object?> fromRemote(String table, Map<String, Object?> row) {
    final types = _types[table]!;
    final out = <String, Object?>{};
    for (final entry in row.entries) {
      final type = types[entry.key];
      if (type == null) continue;
      var value = entry.value;
      if (type == DriftSqlType.bool && value is bool) value = value ? 1 : 0;
      // PostgREST returns bigints as JSON numbers, but a value that overflows
      // a double comes back as a string; and `numeric` columns can too.
      if (value is String && type == DriftSqlType.int) {
        value = int.tryParse(value) ?? value;
      }
      if (value is String && type == DriftSqlType.double) {
        value = double.tryParse(value) ?? value;
      }
      if (value is int && type == DriftSqlType.double) {
        value = value.toDouble();
      }
      out[entry.key] = value;
    }
    return out;
  }
}
