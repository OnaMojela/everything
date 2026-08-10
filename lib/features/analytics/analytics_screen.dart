import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/providers.dart';
import '../shell/app_shell.dart';
import 'finance_analytics.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final showBoth = settings.showProductivity && settings.showFinance;

    return DefaultTabController(
      length: showBoth ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analytics'),
          actions: shellActions(context),
          bottom: showBoth
              ? const TabBar(
                  dividerColor: Colors.transparent,
                  tabs: [Tab(text: 'Productivity'), Tab(text: 'Finance')],
                )
              : null,
        ),
        body: showBoth
            ? const TabBarView(
                children: [_ProductivityAnalytics(), FinanceAnalyticsView()])
            : settings.showFinance
                ? const FinanceAnalyticsView()
                : const _ProductivityAnalytics(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Productivity analytics
// ---------------------------------------------------------------------------

class _ProductivityAnalytics extends ConsumerWidget {
  const _ProductivityAnalytics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final habits = ref.watch(habitsProvider).valueOrNull ?? const [];
    final entries = ref.watch(allEntriesProvider).valueOrNull ?? const [];
    final sessions = ref.watch(focusSessionsProvider).valueOrNull ?? const [];
    final subjects = ref.watch(focusSubjectsProvider).valueOrNull ?? const [];
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const [];

    final byHabit = <String, Map<String, HabitEntry>>{};
    for (final e in entries) {
      (byHabit[e.habitId] ??= {})[e.day] = e;
    }

    // Overall heatmap: fraction of scheduled habits completed per day.
    final heat = <DateTime, double>{};
    for (var i = 0; i < 18 * 7; i++) {
      final d = today.subtract(Duration(days: i));
      final due = habits.where((h) => habitDueOn(h, d)).toList();
      if (due.isEmpty) continue;
      final done =
          due.where((h) => byHabit[h.id]?[dayKey(d)]?.completed ?? false).length;
      heat[d] = done / due.length;
    }

    final bestStreakNow = habits
        .map((h) => currentStreak(h, byHabit[h.id] ?? const {}))
        .fold<int>(0, (a, b) => a > b ? a : b);
    final avgRate = habits.isEmpty
        ? 0.0
        : habits
                .map((h) => completionRate(h, byHabit[h.id] ?? const {}))
                .fold<double>(0, (a, b) => a + b) /
            habits.length;

    final totalFocusSeconds =
        sessions.fold<int>(0, (a, s) => a + s.durationSeconds);
    final weekFocusSeconds = sessions
        .where((s) => !dateOnly(s.startedAt).isBefore(startOfWeek(today)))
        .fold<int>(0, (a, s) => a + s.durationSeconds);
    final avgSession = sessions.isEmpty ? 0 : totalFocusSeconds ~/ sessions.length;
    final longest = sessions.isEmpty
        ? 0
        : sessions.map((s) => s.durationSeconds).reduce((a, b) => a > b ? a : b);

    // Focus minutes for last 7 days
    final focusBars = <double>[];
    for (var i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      focusBars.add(sessions
              .where((s) => dayKey(s.startedAt) == dayKey(d))
              .fold<int>(0, (a, s) => a + s.durationSeconds) /
          60);
    }

    // Subject breakdown
    final bySubject = groupBy(sessions, (FocusSession s) => s.subjectId);
    final subjectTotals = bySubject.entries
        .map((e) => (
              subjects.where((s) => s.id == e.key).firstOrNull,
              e.value.fold<int>(0, (a, s) => a + s.durationSeconds)
            ))
        .sortedBy<num>((t) => -t.$2)
        .toList();

    final completedTasks = tasks.where((t) => t.completed).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s24),
      children: [
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Best streak',
                  value: '$bestStreakNow',
                  icon: Icons.local_fire_department_rounded,
                  color: const Color(0xFFE8590C))),
          const SizedBox(width: Tokens.s12),
          Expanded(
              child: StatTile(
                  label: '30-day consistency',
                  value: '${(avgRate * 100).round()}%',
                  icon: Icons.percent_rounded)),
        ]),
        const SizedBox(height: Tokens.s12),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Tasks completed',
                  value: '$completedTasks',
                  icon: Icons.task_alt_rounded,
                  color: const Color(0xFF2E9E5B))),
          const SizedBox(width: Tokens.s12),
          Expanded(
              child: StatTile(
                  label: 'Focus this week',
                  value: formatDuration(Duration(seconds: weekFocusSeconds)),
                  icon: Icons.center_focus_strong_rounded)),
        ]),
        const SizedBox(height: Tokens.s12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Habit consistency', style: theme.textTheme.titleSmall),
              const SizedBox(height: Tokens.s12),
              HeatmapCalendar(data: heat, color: theme.colorScheme.primary),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Focus Â· last 7 days (minutes)', style: theme.textTheme.titleSmall),
              const SizedBox(height: Tokens.s16),
              SizedBox(
                height: 140,
                child: BarChart(
                  BarChartData(
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) {
                            final d = today.subtract(Duration(days: 6 - v.toInt()));
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < 7; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: focusBars[i] == 0 ? 0.5 : focusBars[i],
                            width: 18,
                            borderRadius: BorderRadius.circular(6),
                            color: focusBars[i] == 0
                                ? theme.colorScheme.outlineVariant
                                : theme.colorScheme.primary,
                          ),
                        ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s12),
        Row(children: [
          Expanded(
              child: StatTile(
                  label: 'Total focus',
                  value: formatDuration(Duration(seconds: totalFocusSeconds)),
                  icon: Icons.hourglass_bottom_rounded)),
          const SizedBox(width: Tokens.s12),
          Expanded(
              child: StatTile(
                  label: 'Avg session',
                  value: formatDuration(Duration(seconds: avgSession)),
                  icon: Icons.av_timer_rounded)),
          const SizedBox(width: Tokens.s12),
          Expanded(
              child: StatTile(
                  label: 'Longest',
                  value: formatDuration(Duration(seconds: longest)),
                  icon: Icons.emoji_events_rounded,
                  color: const Color(0xFFDB8B00))),
        ]),
        if (subjectTotals.isNotEmpty) ...[
          const SizedBox(height: Tokens.s12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('By subject', style: theme.textTheme.titleSmall),
                const SizedBox(height: Tokens.s8),
                for (final (subject, seconds) in subjectTotals.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        IconBadge(
                          icon: subject != null
                              ? appIcon(subject.iconCode)
                              : Icons.center_focus_strong_rounded,
                          color: subject != null
                              ? Color(subject.colorValue)
                              : theme.colorScheme.primary,
                          size: 34,
                        ),
                        const SizedBox(width: Tokens.s12),
                        Expanded(child: Text(subject?.name ?? 'No subject')),
                        Text(formatDuration(Duration(seconds: seconds)),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
