import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:everything/data/db/database.dart';
import 'package:everything/data/sync/supabase_schema_gen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Supabase schema is generated from the Drift schema, so the two cannot
/// quietly diverge. Adding a column to a table and forgetting the server would
/// otherwise show up as rows that sync everywhere except for that one field.
///
/// Regenerate after a schema change with:
///
///     flutter test test/supabase_schema_test.dart --dart-define=WRITE=1
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('checked-in Supabase migration matches the Drift schema', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final generated = generateSupabaseSchema(db);
    final file = File('supabase/migrations/0001_mirror_schema.sql');

    // Any non-empty value counts, so WRITE=1 and WRITE=true both work.
    const write = bool.hasEnvironment('WRITE') &&
        String.fromEnvironment('WRITE') != 'false';
    if (write || !file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(generated);
    }

    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n'),
      generated.replaceAll('\r\n', '\n'),
      reason: 'supabase/migrations/0001_mirror_schema.sql is out of date — '
          'rerun with --dart-define=WRITE=1 and apply it to your project.',
    );
  });
}
