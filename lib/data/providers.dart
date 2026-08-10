import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/utils.dart';
import 'db/database.dart';
import 'logic/domain_logic.dart';
import 'logic/merchant_rules.dart';
import 'models/enums.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ---------------------------------------------------------------------------
// Productivity streams
// ---------------------------------------------------------------------------

final habitsProvider = StreamProvider<List<Habit>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.habits)
        ..where((h) => h.archived.equals(false))
        ..orderBy([(h) => OrderingTerm.asc(h.sortOrder), (h) => OrderingTerm.asc(h.createdAt)]))
      .watch();
});

final archivedHabitsProvider = StreamProvider<List<Habit>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.habits)..where((h) => h.archived.equals(true))).watch();
});

/// All entries for one habit, keyed by day.
final habitEntriesProvider =
    StreamProvider.family<Map<String, HabitEntry>, String>((ref, habitId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.habitEntries)..where((e) => e.habitId.equals(habitId)))
      .watch()
      .map((rows) => {for (final r in rows) r.day: r});
});

/// Entries for every habit on a given day, keyed by habitId.
final entriesForDayProvider =
    StreamProvider.family<Map<String, HabitEntry>, String>((ref, day) {
  final db = ref.watch(dbProvider);
  return (db.select(db.habitEntries)..where((e) => e.day.equals(day)))
      .watch()
      .map((rows) => {for (final r in rows) r.habitId: r});
});

/// All habit entries (for analytics/heatmaps).
final allEntriesProvider = StreamProvider<List<HabitEntry>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.habitEntries).watch();
});

final tasksProvider = StreamProvider<List<Task>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.tasks)
        ..orderBy([
          (t) => OrderingTerm.asc(t.completed),
          (t) => OrderingTerm.asc(t.dueDay),
          (t) => OrderingTerm.desc(t.priority),
          (t) => OrderingTerm.asc(t.sortOrder),
        ]))
      .watch();
});

final subtasksProvider = StreamProvider.family<List<Subtask>, String>((ref, taskId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.subtasks)
        ..where((s) => s.taskId.equals(taskId))
        ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
      .watch();
});

/// Events visible on a given day: one-off blocks anchored to that day plus
/// daily/weekly recurring blocks whose anchor is on or before it.
final plannerEventsProvider =
    StreamProvider.family<List<PlannerEvent>, String>((ref, day) {
  final db = ref.watch(dbProvider);
  final d = parseDayKey(day);
  return (db.select(db.plannerEvents)
        ..where((e) => e.day.equals(day) | e.recurrence.isBiggerThanValue(0)))
      .watch()
      .map((rows) {
    final visible = rows.where((e) {
      if (e.day == day) return true;
      final anchor = parseDayKey(e.day);
      if (anchor.isAfter(d)) return false;
      return switch (PlannerRecurrence.values[e.recurrence]) {
        PlannerRecurrence.none => false,
        PlannerRecurrence.daily => true,
        PlannerRecurrence.weekly => anchor.weekday == d.weekday,
      };
    }).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return visible;
  });
});

final focusSubjectsProvider = StreamProvider<List<FocusSubject>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.focusSubjects)..where((s) => s.archived.equals(false))).watch();
});

final focusSessionsProvider = StreamProvider<List<FocusSession>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.focusSessions)
        ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
      .watch();
});

// ---------------------------------------------------------------------------
// Finance streams
// ---------------------------------------------------------------------------

final accountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.accounts)
        ..where((a) => a.archived.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
      .watch();
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.categories)..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).watch();
});

final transactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.desc(t.day), (t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.budgets)..orderBy([(b) => OrderingTerm.asc(b.sortOrder)])).watch();
});

final billsProvider = StreamProvider<List<Bill>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.bills)
        ..where((b) => b.archived.equals(false))
        ..orderBy([(b) => OrderingTerm.asc(b.nextDue)]))
      .watch();
});

final goalsProvider = StreamProvider<List<Goal>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.goals)..where((g) => g.archived.equals(false))).watch();
});

/// Live balances per account in cents (initial + transaction deltas).
final balancesProvider = Provider<Map<String, int>>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
  final deltas = accountDeltas(txs);
  return {
    for (final a in accounts) a.id: a.initialBalance + (deltas[a.id] ?? 0),
  };
});

final merchantRulesProvider = StreamProvider<List<MerchantRule>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.merchantRules)..orderBy([(r) => OrderingTerm.desc(r.hits)]))
      .watch();
});

final recurringTransactionsProvider = StreamProvider<List<RecurringTransaction>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.recurringTransactions)
        ..orderBy([(r) => OrderingTerm.asc(r.nextRun)]))
      .watch();
});

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

class Repo {
  final AppDatabase db;
  Repo(this.db);

  // -- habits ---------------------------------------------------------------

  /// Set today's (or any day's) progress for a habit. Completion is derived
  /// from the target for measurable habits.
  Future<void> setHabitValue(Habit h, String day, double value, {bool? forceCompleted}) async {
    final type = HabitType.values[h.habitType];
    final completed = forceCompleted ??
        (type == HabitType.check ? value > 0 : h.targetValue > 0 && value >= h.targetValue);
    await db.into(db.habitEntries).insert(
          HabitEntriesCompanion.insert(
            id: '${h.id}_$day',
            habitId: h.id,
            day: day,
            value: Value(value),
            completed: Value(completed),
          ),
          onConflict: DoUpdate(
            (_) => HabitEntriesCompanion(value: Value(value), completed: Value(completed)),
          ),
        );
  }

  Future<void> deleteHabit(String id) =>
      (db.delete(db.habits)..where((h) => h.id.equals(id))).go();

  Future<void> setHabitArchived(String id, bool archived) =>
      (db.update(db.habits)..where((h) => h.id.equals(id)))
          .write(HabitsCompanion(archived: Value(archived)));

  // -- tasks ----------------------------------------------------------------

  /// Roll every overdue, uncompleted task forward to today so nothing is lost.
  Future<void> rolloverTasks() async {
    final key = dayKey(today);
    await (db.update(db.tasks)
          ..where((t) => t.completed.equals(false) & t.dueDay.isSmallerThanValue(key)))
        .write(TasksCompanion(dueDay: Value(key)));
  }

  Future<void> setTaskCompleted(Task t, bool completed) =>
      (db.update(db.tasks)..where((x) => x.id.equals(t.id))).write(TasksCompanion(
        completed: Value(completed),
        completedAt: Value(completed ? DateTime.now() : null),
      ));

  Future<void> deleteTask(String id) =>
      (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();

  // -- planner --------------------------------------------------------------

  Future<void> deletePlannerEvent(String id) =>
      (db.delete(db.plannerEvents)..where((e) => e.id.equals(id))).go();

  // -- focus ----------------------------------------------------------------

  Future<void> recordFocusSession({
    String? subjectId,
    required DateTime startedAt,
    required int durationSeconds,
    int? goalMinutes,
    String note = '',
  }) =>
      db.into(db.focusSessions).insert(FocusSessionsCompanion.insert(
            id: newId(),
            subjectId: Value(subjectId),
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            goalMinutes: Value(goalMinutes),
            note: Value(note),
          ));

  // -- finance --------------------------------------------------------------

  Future<void> deleteTransaction(String id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();

  Future<void> deleteAccount(String id) =>
      (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();

  Future<void> deleteBudget(String id) =>
      (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();

  Future<void> deleteBill(String id) =>
      (db.delete(db.bills)..where((b) => b.id.equals(id))).go();

  Future<void> deleteGoal(String id) =>
      (db.delete(db.goals)..where((g) => g.id.equals(id))).go();

  /// Mark a bill paid: optionally record the expense and advance the due date.
  Future<void> payBill(Bill bill, {bool recordTransaction = true}) async {
    final due = parseDayKey(bill.nextDue);
    if (recordTransaction && bill.accountId != null) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: newId(),
            txType: TxType.expense.index,
            amount: bill.amount,
            accountId: bill.accountId!,
            categoryId: Value(bill.categoryId),
            description: Value(bill.name),
            day: dayKey(today),
            createdAt: DateTime.now(),
          ));
    }
    final next = BillRecurrence.values[bill.recurrence].next(due);
    await (db.update(db.bills)..where((b) => b.id.equals(bill.id))).write(BillsCompanion(
      nextDue: Value(dayKey(next)),
      lastPaid: Value(dayKey(today)),
    ));
  }

  Future<void> addToGoal(Goal g, int amountCents) {
    final next = g.savedAmount + amountCents;
    return (db.update(db.goals)..where((x) => x.id.equals(g.id)))
        .write(GoalsCompanion(savedAmount: Value(next < 0 ? 0 : next)));
  }

  // -- balance sync ---------------------------------------------------------

  /// Makes an account's displayed balance equal the figure the bank reported,
  /// by adjusting its starting balance. Every recorded transaction is kept, so
  /// history and analytics are untouched.
  ///
  /// Returns the difference this correction applied, in cents (0 when the
  /// balance already agreed).
  Future<int> syncAccountBalance(String accountId, int reportedBalanceCents) async {
    final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
    if (account == null) return 0;

    final txs = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId) | t.toAccountId.equals(accountId)))
        .get();
    final delta = accountDeltas(txs)[accountId] ?? 0;

    final newInitial = reconciledInitialBalance(
      reportedBalanceCents: reportedBalanceCents,
      deltaCents: delta,
    );
    final correction = newInitial - account.initialBalance;
    if (correction == 0) return 0;

    await (db.update(db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(initialBalance: Value(newInitial)));
    return correction;
  }

  // -- merchant categorisation ---------------------------------------------

  /// Remembers that [merchant] belongs in [categoryId]. Repeated confirmations
  /// strengthen the rule; a different category replaces it.
  Future<void> learnMerchantCategory(String merchant, String? categoryId) async {
    if (categoryId == null) return;
    final key = MerchantMatching.key(merchant);
    if (key.isEmpty) return;

    final existing = await (db.select(db.merchantRules)
          ..where((r) => r.merchantKey.equals(key)))
        .getSingleOrNull();

    await db.into(db.merchantRules).insertOnConflictUpdate(
          MerchantRulesCompanion.insert(
            merchantKey: key,
            displayName: Value(merchant.trim()),
            categoryId: categoryId,
            hits: Value(existing != null && existing.categoryId == categoryId
                ? existing.hits + 1
                : 1),
            updatedAt: DateTime.now(),
          ),
        );
  }

  /// The category previously used for this merchant, if any.
  Future<String?> suggestCategoryFor(String merchant) async {
    if (MerchantMatching.key(merchant).isEmpty) return null;
    final rules = await db.select(db.merchantRules).get();
    return MerchantMatching.bestMatch(merchant, rules)?.categoryId;
  }

  Future<void> forgetMerchantRule(String key) =>
      (db.delete(db.merchantRules)..where((r) => r.merchantKey.equals(key))).go();

  // -- recurring transactions ----------------------------------------------

  Future<void> deleteRecurring(String id) =>
      (db.delete(db.recurringTransactions)..where((r) => r.id.equals(id))).go();

  /// Post every due standing order, catching up missed runs one by one.
  Future<void> postDueRecurringTransactions() async {
    final due = await (db.select(db.recurringTransactions)
          ..where((r) =>
              r.active.equals(true) &
              r.nextRun.isSmallerOrEqualValue(dayKey(today))))
        .get();
    for (final r in due) {
      var run = parseDayKey(r.nextRun);
      while (!run.isAfter(today)) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: newId(),
              txType: r.txType,
              amount: r.amount,
              accountId: r.accountId,
              toAccountId: Value(r.toAccountId),
              categoryId: Value(r.categoryId),
              description: Value(r.description),
              day: dayKey(run),
              createdAt: DateTime.now(),
            ));
        run = BillRecurrence.values[r.recurrence].next(run);
      }
      await (db.update(db.recurringTransactions)..where((x) => x.id.equals(r.id)))
          .write(RecurringTransactionsCompanion(nextRun: Value(dayKey(run))));
    }
  }

  // -- habit skip -----------------------------------------------------------

  Future<void> setHabitSkipped(Habit h, String day, bool skipped) =>
      db.into(db.habitEntries).insert(
            HabitEntriesCompanion.insert(
              id: '${h.id}_$day',
              habitId: h.id,
              day: day,
              value: const Value(0),
              completed: const Value(false),
              skipped: Value(skipped),
            ),
            onConflict: DoUpdate(
              (_) => HabitEntriesCompanion(
                skipped: Value(skipped),
                completed: const Value(false),
                value: const Value(0),
              ),
            ),
          );

  // -- planner --------------------------------------------------------------

  /// Copy all one-off blocks from [from] into [to].
  Future<int> copyPlannerDay(String from, String to) async {
    final events = await (db.select(db.plannerEvents)
          ..where((e) => e.day.equals(from) & e.recurrence.equals(0)))
        .get();
    for (final e in events) {
      await db.into(db.plannerEvents).insert(PlannerEventsCompanion.insert(
            id: newId(),
            title: e.title,
            day: to,
            startMinutes: e.startMinutes,
            endMinutes: e.endMinutes,
            colorValue: e.colorValue,
            note: Value(e.note),
          ));
    }
    return events.length;
  }
}

final repoProvider = Provider<Repo>((ref) => Repo(ref.watch(dbProvider)));
