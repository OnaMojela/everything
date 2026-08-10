import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

enum _Range { thisMonth, lastMonth, threeMonths, sixMonths, year, all }

extension on _Range {
  String get label => switch (this) {
        _Range.thisMonth => 'This month',
        _Range.lastMonth => 'Last month',
        _Range.threeMonths => '3 months',
        _Range.sixMonths => '6 months',
        _Range.year => 'This year',
        _Range.all => 'All time',
      };

  ({DateTime start, DateTime end}) window() => switch (this) {
        _Range.thisMonth => (start: startOfMonth(today), end: today),
        _Range.lastMonth => (
            start: DateTime(today.year, today.month - 1, 1),
            end: DateTime(today.year, today.month, 0),
          ),
        _Range.threeMonths => (
            start: today.subtract(const Duration(days: 90)),
            end: today
          ),
        _Range.sixMonths => (
            start: today.subtract(const Duration(days: 182)),
            end: today
          ),
        _Range.year => (start: DateTime(today.year, 1, 1), end: today),
        _Range.all => (start: DateTime(2000), end: today),
      };
}

class FinanceAnalyticsView extends ConsumerStatefulWidget {
  const FinanceAnalyticsView({super.key});

  @override
  ConsumerState<FinanceAnalyticsView> createState() => _FinanceAnalyticsViewState();
}

class _FinanceAnalyticsViewState extends ConsumerState<FinanceAnalyticsView> {
  _Range range = _Range.thisMonth;

  static bool _isIncome(Transaction t) =>
      t.txType == TxType.income.index || t.txType == TxType.refund.index;
  static bool _isSpend(Transaction t) =>
      t.txType == TxType.expense.index || t.txType == TxType.investment.index;

  /// Effect on total net worth, in cents (transfers are neutral).
  static int _netWorthEffect(Transaction t) {
    if (t.txType == TxType.transfer.index) return 0;
    return TxType.values[t.txType].sign() * t.amount;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final symbol = settings.currencySymbol;
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final balances = ref.watch(balancesProvider);
    final cats = {
      for (final c in ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        c.id: c
    };

    final w = range.window();
    bool inRange(Transaction t) {
      final d = parseDayKey(t.day);
      return !d.isBefore(w.start) && !d.isAfter(w.end);
    }

    final incomeCents =
        txs.where((t) => inRange(t) && _isIncome(t)).fold<int>(0, (a, t) => a + t.amount);
    final spendCents =
        txs.where((t) => inRange(t) && _isSpend(t)).fold<int>(0, (a, t) => a + t.amount);

    final netWorth = accounts
        .where((a) => a.includeInNetWorth)
        .fold<int>(0, (s, a) => s + (balances[a.id] ?? 0));

    // Net worth at the end of each of the last 12 months, derived backwards
    // from today's balance minus later transaction effects.
    final nwMonths = <DateTime>[
      for (var i = 11; i >= 0; i--) DateTime(today.year, today.month - i, 1)
    ];
    final nwSeries = <double>[];
    for (final m in nwMonths) {
      final end = endOfMonth(m);
      final laterDelta = txs
          .where((t) => parseDayKey(t.day).isAfter(end))
          .fold<int>(0, (a, t) => a + _netWorthEffect(t));
      nwSeries.add((netWorth - laterDelta) / 100);
    }

    // 6-month income/expense trend (fixed window, independent of range chips)
    final months = <DateTime>[
      for (var i = 5; i >= 0; i--) DateTime(today.year, today.month - i, 1)
    ];
    final incomeSeries = <double>[];
    final expenseSeries = <double>[];
    for (final m in months) {
      final end = endOfMonth(m);
      bool inM(Transaction t) {
        final d = parseDayKey(t.day);
        return !d.isBefore(m) && !d.isAfter(end);
      }

      incomeSeries.add(
          txs.where((t) => inM(t) && _isIncome(t)).fold<int>(0, (a, t) => a + t.amount) /
              100);
      expenseSeries.add(
          txs.where((t) => inM(t) && _isSpend(t)).fold<int>(0, (a, t) => a + t.amount) /
              100);
    }

    // Category breakdown for the selected range
    final catTotals = <String?, int>{};
    for (final t in txs.where((t) => inRange(t) && _isSpend(t))) {
      catTotals.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final catList = catTotals.entries.sortedBy<num>((e) => -e.value).toList();
    final catSum = catList.fold<int>(0, (a, e) => a + e.value);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s24),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final r in _Range.values)
                Padding(
                  padding: const EdgeInsets.only(right: Tokens.s8),
                  child: ChoiceChip(
                    label: Text(r.label),
                    selected: range == r,
                    onSelected: (_) => setState(() => range = r),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s12),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Net worth',
                  value: formatMoney(netWorth, symbol),
                  icon: Icons.account_balance_rounded)),
        ]),
        const SizedBox(height: Tokens.s12),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Income · ${range.label}',
                  value: formatMoney(incomeCents, symbol),
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFF2E9E5B))),
          const SizedBox(width: Tokens.s12),
          Expanded(
              child: StatTile(
                  label: 'Spent · ${range.label}',
                  value: formatMoney(spendCents, symbol),
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFFD64545))),
        ]),
        const SizedBox(height: Tokens.s12),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Cash flow · ${range.label}',
                  value: formatMoney(incomeCents - spendCents, symbol, signed: true),
                  icon: Icons.swap_vert_rounded)),
        ]),
        const SizedBox(height: Tokens.s12),
        _chartCard(
          context,
          title: 'Net worth · 12 months',
          child: LineChart(
            LineChartData(
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 3,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('MMM')
                            .format(nwMonths[v.toInt().clamp(0, nwMonths.length - 1)]),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ),
              lineBarsData: [_series(nwSeries, theme.colorScheme.primary)],
            ),
          ),
        ),
        const SizedBox(height: Tokens.s12),
        _chartCard(
          context,
          title: 'Income vs spending · 6 months',
          child: LineChart(
            LineChartData(
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('MMM').format(months[v.toInt().clamp(0, 5)]),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                _series(incomeSeries, const Color(0xFF2E9E5B)),
                _series(expenseSeries, const Color(0xFFD64545)),
              ],
            ),
          ),
        ),
        if (catList.isNotEmpty) ...[
          const SizedBox(height: Tokens.s12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Where the money went · ${range.label}',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: Tokens.s12),
                for (final e in catList.take(8))
                  Builder(builder: (context) {
                    final cat = cats[e.key];
                    final color =
                        cat != null ? Color(cat.colorValue) : theme.colorScheme.primary;
                    final frac = catSum <= 0 ? 0.0 : e.value / catSum;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                  cat != null
                                      ? appIcon(cat.iconCode)
                                      : Icons.category_rounded,
                                  size: 16,
                                  color: color),
                              const SizedBox(width: Tokens.s8),
                              Expanded(child: Text(cat?.name ?? 'Uncategorised')),
                              Text(
                                  '${formatMoney(e.value, symbol)} · ${(frac * 100).round()}%',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ProgressBar(progress: frac, color: color, height: 6),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _chartCard(BuildContext context, {required String title, required Widget child}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Tokens.s16),
          SizedBox(height: 160, child: child),
        ],
      ),
    );
  }

  LineChartBarData _series(List<double> values, Color color) => LineChartBarData(
        spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
        isCurved: true,
        curveSmoothness: .3,
        preventCurveOverShooting: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .08)),
      );
}
