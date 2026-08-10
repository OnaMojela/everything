import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/providers.dart';
import 'habit_editor.dart';
import 'habit_widgets.dart';

class HabitsTab extends ConsumerStatefulWidget {
  const HabitsTab({super.key});

  @override
  ConsumerState<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends ConsumerState<HabitsTab> {
  DateTime selectedDay = today;

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const [];
    final entries =
        ref.watch(entriesForDayProvider(dayKey(selectedDay))).valueOrNull ?? const {};
    final due = habits.where((h) => habitDueOn(h, selectedDay)).toList();
    final rest = habits.where((h) => !habitDueOn(h, selectedDay)).toList();
    final doneCount = due.where((h) => entries[h.id]?.completed ?? false).length;
    final theme = Theme.of(context);

    if (habits.isEmpty) {
      return EmptyState(
        icon: Icons.repeat_rounded,
        title: 'Build your first habit',
        subtitle:
            'Habits repeat on a schedule you choose and can be measured any way you like — checkboxes, counts, litres, minutes or percentages.',
        actionLabel: 'New habit',
        onAction: () => showAppSheet(context, const HabitEditorSheet()),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        _DayStrip(
          selected: selectedDay,
          onChanged: (d) => setState(() => selectedDay = d),
        ),
        const SizedBox(height: Tokens.s12),
        if (due.isNotEmpty) ...[
          SectionHeader(
            dayKey(selectedDay) == dayKey(today)
                ? 'Today · $doneCount/${due.length} done'
                : '${formatDay(selectedDay)} · $doneCount/${due.length} done',
          ),
          AppCard(
            padding:
                const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: Tokens.s8),
            child: Column(
              children: [
                for (final h in due)
                  HabitRow(habit: h, entry: entries[h.id], day: dayKey(selectedDay)),
              ],
            ),
          ),
        ] else
          AppCard(
            child: Row(
              children: [
                Icon(Icons.self_improvement_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: Tokens.s12),
                const Expanded(child: Text('Nothing scheduled for this day.')),
              ],
            ),
          ),
        if (rest.isNotEmpty) ...[
          const SectionHeader('Not scheduled this day'),
          AppCard(
            padding:
                const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: Tokens.s8),
            child: Column(
              children: [
                for (final h in rest)
                  Opacity(
                    opacity: .6,
                    child:
                        HabitRow(habit: h, entry: entries[h.id], day: dayKey(selectedDay)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Horizontal 14-day selector strip.
class _DayStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  const _DayStrip({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = [
      for (var i = -7; i <= 6; i++) today.add(Duration(days: i)),
    ];
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        controller: ScrollController(initialScrollOffset: 7 * 56.0 - 100),
        separatorBuilder: (_, _) => const SizedBox(width: Tokens.s8),
        itemBuilder: (context, i) {
          final d = days[i];
          final isSel = dayKey(d) == dayKey(selected);
          final isToday = dayKey(d) == dayKey(today);
          return GestureDetector(
            onTap: () => onChanged(d),
            child: AnimatedContainer(
              duration: Tokens.fast,
              width: 48,
              decoration: BoxDecoration(
                color: isSel
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Tokens.rControl),
                border: isToday && !isSel
                    ? Border.all(color: theme.colorScheme.primary)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSel
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${d.day}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSel ? theme.colorScheme.onPrimary : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
