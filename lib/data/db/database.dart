import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart' show Icons;

import '../sync/sync_schema.dart';

export '../sync/sync_schema.dart' show SyncKeys, SyncedTable, syncedTables;

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Productivity tables
// ---------------------------------------------------------------------------

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get iconCode => integer()();
  IntColumn get colorValue => integer()();
  IntColumn get habitType => integer()(); // HabitType.index
  RealColumn get targetValue => real().withDefault(const Constant(1))();
  TextColumn get unit => text().withDefault(const Constant(''))();
  IntColumn get scheduleType => integer()(); // ScheduleType.index
  TextColumn get daysOfWeek => text().withDefault(const Constant(''))(); // csv 1..7
  IntColumn get everyN => integer().withDefault(const Constant(2))();
  TextColumn get monthlyDays => text().withDefault(const Constant(''))(); // csv 1..31
  TextColumn get anchorDate => text()(); // yyyy-MM-dd start of schedule
  TextColumn get reminderTime => text().nullable()(); // HH:mm
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class HabitEntries extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get day => text()(); // yyyy-MM-dd
  RealColumn get value => real().withDefault(const Constant(0))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  /// Skipped days (holiday, sick…) don't break streaks and don't count as done.
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, day}
      ];
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get dueDay => text().nullable()(); // yyyy-MM-dd
  TextColumn get dueTime => text().nullable()(); // HH:mm
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get category => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))(); // csv
  IntColumn get estimatedMinutes => integer().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Subtasks extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class PlannerEvents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get day => text()(); // yyyy-MM-dd; anchor day for recurring blocks
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();
  IntColumn get colorValue => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get recurrence => integer().withDefault(const Constant(0))(); // PlannerRecurrence.index

  @override
  Set<Column> get primaryKey => {id};
}

class FocusSubjects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  IntColumn get iconCode => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId =>
      text().nullable().references(FocusSubjects, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  IntColumn get goalMinutes => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Finance tables
// ---------------------------------------------------------------------------

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get accountType => integer()(); // AccountType.index
  IntColumn get colorValue => integer()();
  IntColumn get initialBalance => integer().withDefault(const Constant(0))(); // cents
  BoolColumn get includeInNetWorth => boolean().withDefault(const Constant(true))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Comma-separated hints used to match bank notifications to this account,
  /// e.g. "1234,fnb" (card last four digits and/or bank name).
  TextColumn get notificationHints => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get iconCode => integer()();
  IntColumn get colorValue => integer()();
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get txType => integer()(); // TxType.index
  IntColumn get amount => integer()(); // cents, always positive
  TextColumn get accountId => text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get toAccountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get merchant => text().withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get day => text()(); // yyyy-MM-dd
  TextColumn get time => text().nullable()(); // HH:mm
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get amount => integer()(); // cents
  IntColumn get period => integer()(); // BudgetPeriod.index
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get customStart => text().nullable()(); // yyyy-MM-dd for custom period
  TextColumn get customEnd => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get amount => integer()(); // cents
  TextColumn get accountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get recurrence => integer()(); // BillRecurrence.index
  TextColumn get nextDue => text()(); // yyyy-MM-dd
  TextColumn get lastPaid => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get iconCode => integer()();
  IntColumn get colorValue => integer()();
  IntColumn get targetAmount => integer()(); // cents
  IntColumn get savedAmount => integer().withDefault(const Constant(0))(); // cents
  TextColumn get targetDay => text().nullable()(); // yyyy-MM-dd
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Standing orders: transactions that post themselves on a schedule.
class RecurringTransactions extends Table {
  TextColumn get id => text()();
  IntColumn get txType => integer()(); // TxType.index
  IntColumn get amount => integer()(); // cents
  TextColumn get accountId => text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get toAccountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get recurrence => integer()(); // BillRecurrence.index
  TextColumn get nextRun => text()(); // yyyy-MM-dd
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Candidate transactions captured from bank notifications, awaiting review.
class InboxItems extends Table {
  TextColumn get id => text()();
  TextColumn get packageName => text()();
  TextColumn get appLabel => text().withDefault(const Constant(''))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  DateTimeColumn get receivedAt => dateTime()();

  // Parsed fields (null when the parser couldn't determine them).
  IntColumn get amount => integer().nullable()(); // cents
  IntColumn get txType => integer().nullable()();
  TextColumn get merchant => text().withDefault(const Constant(''))();
  TextColumn get accountLast4 => text().withDefault(const Constant(''))();
  TextColumn get bankName => text().withDefault(const Constant(''))();
  RealColumn get confidence => real().withDefault(const Constant(0))();

  TextColumn get matchedAccountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get createdTransactionId => text().nullable()();

  /// InboxStatus.index
  IntColumn get status => integer().withDefault(const Constant(0))();

  /// Set when this item is a second report of a transaction already captured
  /// from another app — points at the item we kept.
  TextColumn get duplicateOfId => text().nullable()();

  /// Apps that also reported this same transaction, e.g. "Truecaller, Messages".
  TextColumn get alsoSeenFrom => text().withDefault(const Constant(''))();

  /// Category learned from how this merchant was categorised before.
  TextColumn get suggestedCategoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();

  /// Balance the bank reported in this message, in cents.
  IntColumn get availableBalance => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Remembers how a merchant was categorised so future transactions from the
/// same place categorise themselves.
class MerchantRules extends Table {
  /// Normalised merchant name — see `merchantKey()`.
  TextColumn get merchantKey => text()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();

  /// How often this rule has been confirmed; higher wins on conflict.
  IntColumn get hits => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {merchantKey};
}

@DriftDatabase(tables: [
  Habits,
  HabitEntries,
  Tasks,
  Subtasks,
  PlannerEvents,
  FocusSubjects,
  FocusSessions,
  Accounts,
  Categories,
  Transactions,
  Budgets,
  Bills,
  Goals,
  RecurringTransactions,
  InboxItems,
  MerchantRules,
  SyncChanges,
  SyncState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : super(driftDatabase(
          name: 'everything',
          // On web the database lives in OPFS (or IndexedDB as a fallback);
          // both assets are served from web/.
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ));

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // ignore_for_file: experimental_member_use
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 -> v2: money moves from REAL currency units to INTEGER cents,
            // habits gain skip days, planner gains recurrence, and standing
            // orders arrive. Disable FKs while tables are rebuilt.
            await customStatement('PRAGMA foreign_keys = OFF');
            await m.addColumn(habitEntries, habitEntries.skipped);
            await m.addColumn(plannerEvents, plannerEvents.recurrence);
            await m.createTable(recurringTransactions);
            await m.alterTable(TableMigration(accounts, columnTransformer: {
              accounts.initialBalance: const CustomExpression(
                  'CAST(ROUND(initial_balance * 100) AS INTEGER)'),
            }));
            await m.alterTable(TableMigration(transactions, columnTransformer: {
              transactions.amount:
                  const CustomExpression('CAST(ROUND(amount * 100) AS INTEGER)'),
            }));
            await m.alterTable(TableMigration(budgets, columnTransformer: {
              budgets.amount:
                  const CustomExpression('CAST(ROUND(amount * 100) AS INTEGER)'),
            }));
            await m.alterTable(TableMigration(bills, columnTransformer: {
              bills.amount:
                  const CustomExpression('CAST(ROUND(amount * 100) AS INTEGER)'),
            }));
            await m.alterTable(TableMigration(goals, columnTransformer: {
              goals.targetAmount: const CustomExpression(
                  'CAST(ROUND(target_amount * 100) AS INTEGER)'),
              goals.savedAmount: const CustomExpression(
                  'CAST(ROUND(saved_amount * 100) AS INTEGER)'),
            }));
          }
          if (from < 3) {
            // v2 -> v3: bank-notification capture.
            await m.addColumn(accounts, accounts.notificationHints);
            await m.createTable(inboxItems);
          }
          if (from < 4) {
            // v3 -> v4: duplicate detection across apps.
            await m.addColumn(inboxItems, inboxItems.duplicateOfId);
            await m.addColumn(inboxItems, inboxItems.alsoSeenFrom);
          }
          if (from < 5) {
            // v4 -> v5: merchants remember their category.
            await m.createTable(merchantRules);
            await m.addColumn(inboxItems, inboxItems.suggestedCategoryId);
          }
          if (from < 6) {
            // v5 -> v6: balances reported by the bank.
            await m.addColumn(inboxItems, inboxItems.availableBalance);
          }
          if (from < 7) {
            // v6 -> v7: cross-device sync bookkeeping. Everything already in
            // the database predates any account, so it is left unqueued; the
            // first sign-in decides whether to upload it.
            await m.createTable(syncChanges);
            await m.createTable(syncState);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // SQLite fires triggers for rows removed by ON DELETE CASCADE only
          // when recursive triggers are enabled. Without this, deleting a
          // habit would tombstone the habit but not its entries, and those
          // entries would survive on every other device. Safe here because no
          // change-log trigger writes to a table that itself has triggers.
          await customStatement('PRAGMA recursive_triggers = ON');
          if (details.wasCreated) await _seedDefaults();
          // Triggers live outside the schema version: recreating them on every
          // open keeps them correct after a migration adds or renames a table.
          await installChangeLog();
        },
      );

  /// (Re)creates the triggers that record local edits for the sync engine.
  Future<void> installChangeLog() async {
    for (final sql in changeLogTriggers()) {
      await customStatement(sql);
    }
  }

  /// Runs [action] without recording anything into the change log, so rows
  /// arriving from the server are not queued straight back for push.
  Future<T> withoutChangeLog<T>(Future<T> Function() action) async {
    await customStatement(suppressChangeLogSql);
    try {
      return await action();
    } finally {
      await customStatement(resumeChangeLogSql);
    }
  }

  /// Empties every user table and all sync bookkeeping, then re-seeds the
  /// default categories. Used when signing out, and when a different account
  /// signs in on this device.
  Future<void> wipeLocalData() async {
    for (final sql in dropChangeLogTriggers()) {
      await customStatement(sql);
    }
    await transaction(() async {
      // `syncedTables` lists parents first, so reversing deletes children
      // before the rows they reference and no foreign key is ever violated.
      // (Toggling `PRAGMA foreign_keys` would not help here — it is a no-op
      // inside a transaction.)
      for (final t in syncedTables.reversed) {
        await customStatement('DELETE FROM ${t.name}');
      }
      await delete(syncChanges).go();
      await delete(syncState).go();
      await _seedDefaults();
    });
    await installChangeLog();
  }

  /// Sensible default finance categories so the app is useful immediately.
  Future<void> _seedDefaults() async {
    final defaults = [
      ('Groceries', Icons.shopping_cart_rounded.codePoint, 0xFF2E9E5B, false),
      ('Eating out', Icons.restaurant_rounded.codePoint, 0xFFE8590C, false),
      ('Transport', Icons.directions_car_rounded.codePoint, 0xFF0B84FF, false),
      ('Housing', Icons.home_rounded.codePoint, 0xFF8E4EC6, false),
      ('Utilities', Icons.bolt_rounded.codePoint, 0xFF0CA5A5, false),
      ('Health', Icons.medication_rounded.codePoint, 0xFFD64545, false),
      ('Entertainment', Icons.sports_esports_rounded.codePoint, 0xFFD6437E, false),
      ('Shopping', Icons.shopping_bag_rounded.codePoint, 0xFFDB8B00, false),
      ('Subscriptions', Icons.subscriptions_rounded.codePoint, 0xFF5B5BD6, false),
      ('Other', Icons.category_rounded.codePoint, 0xFF5C6470, false),
      ('Salary', Icons.work_rounded.codePoint, 0xFF2E9E5B, true),
      ('Freelance', Icons.laptop_mac_rounded.codePoint, 0xFF0B84FF, true),
      ('Gifts', Icons.card_giftcard_rounded.codePoint, 0xFFD6437E, true),
      ('Interest', Icons.trending_up_rounded.codePoint, 0xFF0CA5A5, true),
    ];
    var i = 0;
    for (final (name, icon, color, income) in defaults) {
      await into(categories).insert(CategoriesCompanion.insert(
        id: 'cat_${name.toLowerCase().replaceAll(' ', '_')}',
        name: name,
        iconCode: icon,
        colorValue: color,
        isIncome: Value(income),
        sortOrder: Value(i++),
      ));
    }
  }
}
