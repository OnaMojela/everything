import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import 'habit_editor.dart';
import 'habit_widgets.dart';

final _habitProvider = StreamProvider.family<Habit?, String>((ref, id) {
  final db = ref.watch(dbProvider);
  return (db.select(db.habits)..where((h) => h.id.equals(id))).watchSingleOrNull();
});

class HabitDetailScreen extends ConsumerWidget {
  final String habitId;
  const HabitDetailScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = ref.watch(_habitProvider(habitId)).valueOrNull;
    if (habit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entries = ref.watch(habitEntriesProvider(habitId)).valueOrNull ?? const {};
    final color = Color(habit.colorValue);
    final theme = Theme.of(context);

    final streak = currentStreak(habit, entries);
    final best = bestStreak(habit, entries);
    final rate30 = completionRate(habit, entries, days: 30);
    final totalDone = entries.values.where((e) => e.completed).length;

    final heatData = <DateTime, double>{
      for (final e in entries.values)
        parseDayKey(e.day): HabitType.values[habit.habitType] == HabitType.check
            ? (e.completed ? 1.0 : 0.0)
            : (habit.targetValue > 0 ? (e.value / habit.targetValue).clamp(0.0, 1.0) : 0.0),
    };

    final history = entries.values.toList()..sort((a, b) => b.day.compareTo(a.day));

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showAppSheet(context, HabitEditorSheet(existing: habit)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(repoProvider);
              if (v == 'archive') {
                await repo.setHabitArchived(habit.id, !habit.archived);
                if (context.mounted) Navigator.pop(context);
              } else if (v == 'delete') {
                if (await confirmDelete(context, 'habit')) {
                  await repo.deleteHabit(habit.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'archive',
                  child: Text(habit.archived ? 'Unarchive' : 'Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s24),
        children: [
          AppCard(
            child: Row(
              children: [
                IconBadge(
                    icon: appIcon(habit.iconCode),
                    color: color,
                    size: 54),
                const SizedBox(width: Tokens.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (habit.description.isNotEmpty)
                        Text(habit.description, style: theme.textTheme.bodyMedium),
                      Text(
                        [
                          habitScheduleLabel(habit),
                          if (habitTargetLabel(habit).isNotEmpty) habitTargetLabel(habit),
                        ].join(' · '),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s12),
          if (habitDueOn(habit, today))
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today', style: theme.textTheme.titleSmall),
                  HabitRow(habit: habit, entry: entries[dayKey(today)]),
                ],
              ),
            ),
          const SizedBox(height: Tokens.s12),
          Row(
            children: [
              Expanded(
                  child: StatTile(
                      label: 'Streak',
                      value: '$streak',
                      icon: Icons.local_fire_department_rounded,
                      color: const Color(0xFFE8590C))),
              const SizedBox(width: Tokens.s12),
              Expanded(
                  child: StatTile(
                      label: 'Best',
                      value: '$best',
                      icon: Icons.emoji_events_rounded,
                      color: const Color(0xFFDB8B00))),
            ],
          ),
          const SizedBox(height: Tokens.s12),
          Row(
            children: [
              Expanded(
                  child: StatTile(
                      label: '30-day rate',
                      value: '${(rate30 * 100).round()}%',
                      icon: Icons.percent_rounded)),
              const SizedBox(width: Tokens.s12),
              Expanded(
                  child: StatTile(
                      label: 'Times done',
                      value: '$totalDone',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF2E9E5B))),
            ],
          ),
          const SizedBox(height: Tokens.s12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('History', style: theme.textTheme.titleSmall),
                const SizedBox(height: Tokens.s12),
                HeatmapCalendar(data: heatData, color: color),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weekly trend', style: theme.textTheme.titleSmall),
                const SizedBox(height: Tokens.s16),
                SizedBox(
                  height: 120,
                  child: _WeeklyTrendChart(habit: habit, entries: entries, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s12),
          if (history.isNotEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent entries', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Tokens.s8),
                  for (final e in history.take(14))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            e.completed
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: e.completed ? color : theme.colorScheme.outlineVariant,
                          ),
                          const SizedBox(width: Tokens.s12),
                          Expanded(child: Text(formatDay(parseDayKey(e.day)))),
                          if (HabitType.values[habit.habitType] != HabitType.check)
                            Text('${trimNum(e.value)} ${habit.unit}'.trim(),
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (habit.note.isNotEmpty) ...[
            const SizedBox(height: Tokens.s12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Tokens.s8),
                  Text(habit.note),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Completion percentage for each of the last 12 weeks.
class _WeeklyTrendChart extends StatelessWidget {
  final Habit habit;
  final Map<String, HabitEntry> entries;
  final Color color;

  const _WeeklyTrendChart(
      {required this.habit, required this.entries, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rates = <double>[];
    for (var i = 11; i >= 0; i--) {
      final ws = startOfWeek(today).subtract(Duration(days: 7 * i));
      rates.add(_weekRate(ws));
    }
    return BarChart(
      BarChartData(
        maxY: 1,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: [
          for (var i = 0; i < rates.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: rates[i] == 0 ? 0.03 : rates[i],
                width: 14,
                borderRadius: BorderRadius.circular(4),
                color: rates[i] == 0 ? theme.colorScheme.outlineVariant : color,
              ),
            ]),
        ],
      ),
    );
  }

  double _weekRate(DateTime weekStart) {
    if (isQuotaHabit(habit)) {
      return (weekCompletions(habit, entries, weekStart) / habitQuota(habit))
          .clamp(0.0, 1.0);
    }
    var scheduled = 0, done = 0;
    for (var i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      if (d.isAfter(today) || !habitDueOn(habit, d)) continue;
      final e = entries[dayKey(d)];
      if (e?.skipped ?? false) continue;
      scheduled++;
      if (e?.completed ?? false) done++;
    }
    return scheduled == 0 ? 0 : done / scheduled;
  }
}

/// Quick editor for the free-form note attached to a habit.
Future<void> editHabitNote(BuildContext context, WidgetRef ref, Habit habit) async {
  final ctrl = TextEditingController(text: habit.note);
  await showAppSheet(
    context,
    SheetScaffold(
      title: 'Notes',
      actionLabel: 'Save',
      onAction: () async {
        final db = ref.read(dbProvider);
        await (db.update(db.habits)..where((h) => h.id.equals(habit.id)))
            .write(HabitsCompanion(note: Value(ctrl.text)));
        if (context.mounted) Navigator.pop(context);
      },
      children: [
        TextField(controller: ctrl, maxLines: 5, autofocus: true),
      ],
    ),
  );
}
