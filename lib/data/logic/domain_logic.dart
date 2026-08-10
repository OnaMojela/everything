import '../../core/utils/utils.dart';
import '../db/database.dart';
import '../models/enums.dart';

// ---------------------------------------------------------------------------
// Habit scheduling
// ---------------------------------------------------------------------------

List<int> _csvInts(String csv) =>
    csv.isEmpty ? const [] : csv.split(',').map(int.parse).toList();

bool isQuotaHabit(Habit h) =>
    ScheduleType.values[h.scheduleType] == ScheduleType.timesPerWeek;

/// For quota habits [everyN] doubles as the weekly target.
int habitQuota(Habit h) => h.everyN < 1 ? 1 : h.everyN;

bool habitDueOn(Habit h, DateTime day) {
  final d = dateOnly(day);
  final anchor = parseDayKey(h.anchorDate);
  if (d.isBefore(dateOnly(anchor))) return false;
  switch (ScheduleType.values[h.scheduleType]) {
    case ScheduleType.daily:
      return true;
    case ScheduleType.weekdays:
      return d.weekday <= 5;
    case ScheduleType.weekends:
      return d.weekday >= 6;
    case ScheduleType.customDays:
      return _csvInts(h.daysOfWeek).contains(d.weekday);
    case ScheduleType.everyN:
      final n = h.everyN < 1 ? 1 : h.everyN;
      return d.difference(dateOnly(anchor)).inDays % n == 0;
    case ScheduleType.monthlyDays:
      return _csvInts(h.monthlyDays).contains(d.day);
    case ScheduleType.yearly:
      return d.month == anchor.month && d.day == anchor.day;
    case ScheduleType.timesPerWeek:
      // Doable any day; the weekly quota tracks overall progress.
      return true;
  }
}

/// Completed days within the week starting at [weekStart].
int weekCompletions(Habit h, Map<String, HabitEntry> byDay, DateTime weekStart) {
  var c = 0;
  for (var i = 0; i < 7; i++) {
    final e = byDay[dayKey(weekStart.add(Duration(days: i)))];
    if (e != null && e.completed) c++;
  }
  return c;
}

String habitScheduleLabel(Habit h) {
  switch (ScheduleType.values[h.scheduleType]) {
    case ScheduleType.daily:
      return 'Every day';
    case ScheduleType.weekdays:
      return 'Weekdays';
    case ScheduleType.weekends:
      return 'Weekends';
    case ScheduleType.customDays:
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final days = _csvInts(h.daysOfWeek).map((d) => names[d - 1]).join(', ');
      return days.isEmpty ? 'Specific weekdays' : days;
    case ScheduleType.everyN:
      return 'Every ${h.everyN} days';
    case ScheduleType.monthlyDays:
      final days = _csvInts(h.monthlyDays).join(', ');
      return days.isEmpty ? 'Monthly' : 'Monthly on $days';
    case ScheduleType.yearly:
      return 'Yearly on ${formatDay(parseDayKey(h.anchorDate))}';
    case ScheduleType.timesPerWeek:
      return '${habitQuota(h)}× per week';
  }
}

/// Target label like "2 L", "30 min", "10 pages" or empty for checkboxes.
String habitTargetLabel(Habit h) {
  final type = HabitType.values[h.habitType];
  if (type == HabitType.check) return '';
  final unit = switch (type) {
    HabitType.duration => 'min',
    HabitType.percent => '%',
    _ => h.unit,
  };
  return '${trimNum(h.targetValue)}${unit.isEmpty ? '' : ' $unit'}'.trim();
}

double habitProgress(Habit h, HabitEntry? e) {
  if (e == null) return 0;
  if (HabitType.values[h.habitType] == HabitType.check) return e.completed ? 1 : 0;
  if (h.targetValue <= 0) return e.completed ? 1 : 0;
  return (e.value / h.targetValue).clamp(0.0, 1.0);
}

/// Current streak. Day-scheduled habits count consecutive completed scheduled
/// days (today pending doesn't break; skipped days pass through). Weekly-quota
/// habits count consecutive weeks meeting the quota (current week pending
/// doesn't break).
int currentStreak(Habit h, Map<String, HabitEntry> byDay) {
  final anchor = dateOnly(parseDayKey(h.anchorDate));
  if (isQuotaHabit(h)) {
    var streak = 0;
    var ws = startOfWeek(today);
    var isCurrent = true;
    for (var i = 0; i < 530; i++) {
      if (ws.add(const Duration(days: 6)).isBefore(anchor)) break;
      final met = weekCompletions(h, byDay, ws) >= habitQuota(h);
      if (met) {
        streak++;
      } else if (!isCurrent) {
        break;
      }
      isCurrent = false;
      ws = ws.subtract(const Duration(days: 7));
    }
    return streak;
  }
  var streak = 0;
  var d = today;
  var isFirst = true;
  for (var i = 0; i < 3660; i++) {
    if (d.isBefore(anchor)) break;
    if (habitDueOn(h, d)) {
      final e = byDay[dayKey(d)];
      if (e?.skipped ?? false) {
        // Skipped: neither counts nor breaks.
      } else if (e?.completed ?? false) {
        streak++;
        isFirst = false;
      } else if (isFirst) {
        // today still pending — don't break
        isFirst = false;
      } else {
        break;
      }
    }
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

int bestStreak(Habit h, Map<String, HabitEntry> byDay) {
  final anchor = dateOnly(parseDayKey(h.anchorDate));
  if (isQuotaHabit(h)) {
    var best = 0, run = 0;
    final currentWeek = startOfWeek(today);
    for (var ws = startOfWeek(anchor);
        !ws.isAfter(currentWeek);
        ws = ws.add(const Duration(days: 7))) {
      if (weekCompletions(h, byDay, ws) >= habitQuota(h)) {
        run++;
        if (run > best) best = run;
      } else if (ws != currentWeek) {
        run = 0;
      }
    }
    return best;
  }
  var best = 0, run = 0;
  for (var d = anchor; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
    if (!habitDueOn(h, d)) continue;
    final e = byDay[dayKey(d)];
    if (e?.skipped ?? false) continue;
    if (e?.completed ?? false) {
      run++;
      if (run > best) best = run;
    } else if (!(dayKey(d) == dayKey(today))) {
      run = 0;
    }
  }
  return best;
}

/// Completion rate over the last [days] days. Skipped days are excluded;
/// quota habits measure completed days against the pro-rated weekly quota.
double completionRate(Habit h, Map<String, HabitEntry> byDay, {int days = 30}) {
  final anchor = dateOnly(parseDayKey(h.anchorDate));
  final from = today.subtract(Duration(days: days - 1));
  if (isQuotaHabit(h)) {
    final start = from.isBefore(anchor) ? anchor : from;
    final daysSpan = today.difference(start).inDays + 1;
    final expected = habitQuota(h) * daysSpan / 7;
    var done = 0;
    for (var d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      if (byDay[dayKey(d)]?.completed ?? false) done++;
    }
    return expected <= 0 ? 0 : (done / expected).clamp(0.0, 1.0);
  }
  var scheduled = 0, done = 0;
  for (var d = from; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
    if (d.isBefore(anchor) || !habitDueOn(h, d)) continue;
    final e = byDay[dayKey(d)];
    if (e?.skipped ?? false) continue;
    scheduled++;
    if (e?.completed ?? false) done++;
  }
  return scheduled == 0 ? 0 : done / scheduled;
}

// ---------------------------------------------------------------------------
// Finance
// ---------------------------------------------------------------------------

/// Net effect of all transactions per account id, in cents.
Map<String, int> accountDeltas(List<Transaction> txs) {
  final map = <String, int>{};
  for (final t in txs) {
    final type = TxType.values[t.txType];
    map.update(t.accountId, (v) => v + type.sign() * t.amount,
        ifAbsent: () => type.sign() * t.amount);
    if (type == TxType.transfer && t.toAccountId != null) {
      map.update(t.toAccountId!, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
  }
  return map;
}

/// Account types where "available balance" really is the account's balance.
/// On a credit card or loan it means available *credit*, which is a different
/// number entirely, so those are never synced automatically.
bool balanceSyncSuitable(Account a) {
  return switch (AccountType.values[a.accountType]) {
    AccountType.checking ||
    AccountType.savings ||
    AccountType.cash ||
    AccountType.custom =>
      true,
    AccountType.creditCard ||
    AccountType.loan ||
    AccountType.investment ||
    AccountType.crypto =>
      false,
  };
}

/// Balances are derived (`initialBalance + transaction deltas`), so to make the
/// displayed balance equal what the bank reported we adjust the starting
/// balance. Returns the new starting balance, in cents.
///
/// [delta] is the net effect of every transaction on the account.
int reconciledInitialBalance({
  required int reportedBalanceCents,
  required int deltaCents,
}) =>
    reportedBalanceCents - deltaCents;

({DateTime start, DateTime end}) budgetWindow(Budget b, DateTime ref, {bool mondayStart = true}) {
  switch (BudgetPeriod.values[b.period]) {
    case BudgetPeriod.weekly:
      final s = startOfWeek(ref, mondayStart: mondayStart);
      return (start: s, end: s.add(const Duration(days: 6)));
    case BudgetPeriod.monthly:
      return (start: startOfMonth(ref), end: endOfMonth(ref));
    case BudgetPeriod.yearly:
      return (start: DateTime(ref.year, 1, 1), end: DateTime(ref.year, 12, 31));
    case BudgetPeriod.custom:
      return (
        start: b.customStart != null ? parseDayKey(b.customStart!) : startOfMonth(ref),
        end: b.customEnd != null ? parseDayKey(b.customEnd!) : endOfMonth(ref),
      );
  }
}

/// Spend against a budget within its current window, in cents.
int budgetSpent(Budget b, List<Transaction> txs, {bool mondayStart = true}) {
  final w = budgetWindow(b, today, mondayStart: mondayStart);
  var total = 0;
  for (final t in txs) {
    final type = TxType.values[t.txType];
    if (type != TxType.expense && type != TxType.investment) continue;
    if (b.categoryId != null && t.categoryId != b.categoryId) continue;
    if (b.accountId != null && t.accountId != b.accountId) continue;
    final d = parseDayKey(t.day);
    if (d.isBefore(w.start) || d.isAfter(w.end)) continue;
    total += t.amount;
  }
  return total;
}
