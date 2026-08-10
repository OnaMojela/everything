import 'package:flutter/material.dart';

/// How a habit is completed / measured.
enum HabitType { check, counter, numeric, duration, percent }

extension HabitTypeX on HabitType {
  String get label => switch (this) {
        HabitType.check => 'Checkbox',
        HabitType.counter => 'Counter',
        HabitType.numeric => 'Numeric value',
        HabitType.duration => 'Duration',
        HabitType.percent => 'Percentage',
      };

  IconData get icon => switch (this) {
        HabitType.check => Icons.check_circle_outline_rounded,
        HabitType.counter => Icons.exposure_plus_1_rounded,
        HabitType.numeric => Icons.numbers_rounded,
        HabitType.duration => Icons.timer_outlined,
        HabitType.percent => Icons.percent_rounded,
      };
}

/// Note: [timesPerWeek] must stay last — indexes are persisted.
enum ScheduleType { daily, weekdays, weekends, customDays, everyN, monthlyDays, yearly, timesPerWeek }

extension ScheduleTypeX on ScheduleType {
  String get label => switch (this) {
        ScheduleType.daily => 'Every day',
        ScheduleType.weekdays => 'Weekdays',
        ScheduleType.weekends => 'Weekends',
        ScheduleType.customDays => 'Specific weekdays',
        ScheduleType.everyN => 'Every X days',
        ScheduleType.monthlyDays => 'Days of month',
        ScheduleType.yearly => 'Once a year',
        ScheduleType.timesPerWeek => 'X times per week',
      };
}

/// Order is persisted — append only.
enum InboxStatus { pending, confirmed, ignored, duplicate }

enum PlannerRecurrence { none, daily, weekly }

extension PlannerRecurrenceX on PlannerRecurrence {
  String get label => switch (this) {
        PlannerRecurrence.none => 'Once',
        PlannerRecurrence.daily => 'Every day',
        PlannerRecurrence.weekly => 'Weekly',
      };
}

enum TaskPriority { none, low, medium, high }

extension TaskPriorityX on TaskPriority {
  String get label => switch (this) {
        TaskPriority.none => 'None',
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
      };

  Color get color => switch (this) {
        TaskPriority.none => const Color(0xFF8E8E93),
        TaskPriority.low => const Color(0xFF0B84FF),
        TaskPriority.medium => const Color(0xFFDB8B00),
        TaskPriority.high => const Color(0xFFD64545),
      };
}

enum AccountType { checking, savings, cash, creditCard, investment, loan, crypto, custom }

extension AccountTypeX on AccountType {
  String get label => switch (this) {
        AccountType.checking => 'Checking',
        AccountType.savings => 'Savings',
        AccountType.cash => 'Cash',
        AccountType.creditCard => 'Credit card',
        AccountType.investment => 'Investment',
        AccountType.loan => 'Loan',
        AccountType.crypto => 'Crypto',
        AccountType.custom => 'Custom',
      };

  IconData get icon => switch (this) {
        AccountType.checking => Icons.account_balance_rounded,
        AccountType.savings => Icons.savings_rounded,
        AccountType.cash => Icons.payments_rounded,
        AccountType.creditCard => Icons.credit_card_rounded,
        AccountType.investment => Icons.trending_up_rounded,
        AccountType.loan => Icons.request_quote_rounded,
        AccountType.crypto => Icons.currency_bitcoin_rounded,
        AccountType.custom => Icons.account_balance_wallet_rounded,
      };
}

enum TxType { expense, income, transfer, refund, investment }

extension TxTypeX on TxType {
  String get label => switch (this) {
        TxType.expense => 'Expense',
        TxType.income => 'Income',
        TxType.transfer => 'Transfer',
        TxType.refund => 'Refund',
        TxType.investment => 'Investment',
      };

  /// Effect on the source account balance.
  int sign() => switch (this) {
        TxType.expense || TxType.investment || TxType.transfer => -1,
        TxType.income || TxType.refund => 1,
      };
}

enum BudgetPeriod { weekly, monthly, yearly, custom }

extension BudgetPeriodX on BudgetPeriod {
  String get label => switch (this) {
        BudgetPeriod.weekly => 'Weekly',
        BudgetPeriod.monthly => 'Monthly',
        BudgetPeriod.yearly => 'Yearly',
        BudgetPeriod.custom => 'Custom',
      };
}

enum BillRecurrence { weekly, monthly, yearly }

extension BillRecurrenceX on BillRecurrence {
  String get label => switch (this) {
        BillRecurrence.weekly => 'Weekly',
        BillRecurrence.monthly => 'Monthly',
        BillRecurrence.yearly => 'Yearly',
      };

  DateTime next(DateTime from) => switch (this) {
        BillRecurrence.weekly => from.add(const Duration(days: 7)),
        BillRecurrence.monthly => DateTime(from.year, from.month + 1, from.day),
        BillRecurrence.yearly => DateTime(from.year + 1, from.month, from.day),
      };
}
