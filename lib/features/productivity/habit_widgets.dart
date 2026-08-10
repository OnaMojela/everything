import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// One habit row with a completion control appropriate to its type.
/// Used on the dashboard (dense) and the habits tab.
class HabitRow extends ConsumerWidget {
  final Habit habit;
  final HabitEntry? entry;
  final bool dense;
  final String? day; // defaults to today

  const HabitRow({super.key, required this.habit, required this.entry, this.dense = false, this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final type = HabitType.values[habit.habitType];
    final color = Color(habit.colorValue);
    final progress = habitProgress(habit, entry);
    final completed = entry?.completed ?? false;
    final value = entry?.value ?? 0;
    final targetLabel = habitTargetLabel(habit);
    final d = day ?? dayKey(today);

    final skipped = entry?.skipped ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.rControl),
      onTap: () => context.push('/habit/${habit.id}'),
      onLongPress: () => _showSkipMenu(context, ref, skipped, d),
      child: Opacity(
        opacity: skipped ? .55 : 1,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 5 : 8),
          child: Row(
            children: [
              ProgressRing(
                progress: progress,
                color: color,
                size: dense ? 38 : 46,
                center: Icon(appIcon(habit.iconCode),
                    size: dense ? 16 : 20, color: color),
              ),
              const SizedBox(width: Tokens.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: completed ? TextDecoration.lineThrough : null,
                        color: completed ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (skipped)
                      Text('Skipped — streak safe',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                    else if (type != HabitType.check)
                      Text(
                        '${trimNum(value)} / $targetLabel',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.s8),
              if (skipped)
                IconButton(
                  tooltip: 'Undo skip',
                  icon: const Icon(Icons.undo_rounded, size: 20),
                  onPressed: () =>
                      ref.read(repoProvider).setHabitSkipped(habit, d, false),
                )
              else
                _control(context, ref, type, color, value, completed, d),
            ],
          ),
        ),
      ),
    );
  }

  void _showSkipMenu(BuildContext context, WidgetRef ref, bool skipped, String d) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(skipped ? Icons.undo_rounded : Icons.redo_rounded),
              title: Text(skipped ? 'Undo skip' : 'Skip this day'),
              subtitle: skipped
                  ? null
                  : const Text('Holiday, sick day… your streak stays safe'),
              onTap: () {
                ref.read(repoProvider).setHabitSkipped(habit, d, !skipped);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open habit'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/habit/${habit.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _control(BuildContext context, WidgetRef ref, HabitType type, Color color,
      double value, bool completed, String d) {
    final repo = ref.read(repoProvider);
    switch (type) {
      case HabitType.check:
        return Checkbox(
          value: completed,
          shape: const CircleBorder(),
          activeColor: color,
          onChanged: (v) => repo.setHabitValue(habit, d, (v ?? false) ? 1 : 0),
        );
      case HabitType.counter:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_rounded, size: 20),
              onPressed:
                  value <= 0 ? null : () => repo.setHabitValue(habit, d, value - 1),
            ),
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: () => repo.setHabitValue(habit, d, value + 1),
            ),
          ],
        );
      case HabitType.numeric:
      case HabitType.duration:
      case HabitType.percent:
        return FilledButton.tonal(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: () => showAppSheet(
              context, HabitValueSheet(habit: habit, entry: entry, day: d)),
          child: Text(completed ? 'Done' : 'Log'),
        );
    }
  }
}

/// Bottom sheet for logging a measurable habit's value (slider + quick steps).
class HabitValueSheet extends ConsumerStatefulWidget {
  final Habit habit;
  final HabitEntry? entry;
  final String day;

  const HabitValueSheet({super.key, required this.habit, required this.entry, required this.day});

  @override
  ConsumerState<HabitValueSheet> createState() => _HabitValueSheetState();
}

class _HabitValueSheetState extends ConsumerState<HabitValueSheet> {
  late double value = widget.entry?.value ?? 0;

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final type = HabitType.values[habit.habitType];
    final color = Color(habit.colorValue);
    final max = type == HabitType.percent
        ? 100.0
        : (habit.targetValue * 2).clamp(1.0, double.infinity);
    final unit = switch (type) {
      HabitType.duration => 'min',
      HabitType.percent => '%',
      _ => habit.unit,
    };

    return SheetScaffold(
      title: habit.title,
      actionLabel: 'Save',
      onAction: () {
        ref.read(repoProvider).setHabitValue(habit, widget.day, value);
        Navigator.pop(context);
      },
      children: [
        Center(
          child: Column(
            children: [
              ProgressRing(
                progress: habit.targetValue <= 0 ? 0 : value / habit.targetValue,
                color: color,
                size: 110,
                strokeWidth: 9,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(trimNum(value), style: Theme.of(context).textTheme.headlineMedium),
                    Text('of ${trimNum(habit.targetValue)} $unit',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: Tokens.s16),
              Slider(
                value: value.clamp(0, max),
                min: 0,
                max: max,
                activeColor: color,
                onChanged: (v) => setState(() {
                  value = type == HabitType.duration || type == HabitType.percent
                      ? v.roundToDouble()
                      : (v * 10).round() / 10;
                }),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final step in _steps(type, habit))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(
                        label: Text('+${trimNum(step)}'),
                        onPressed: () => setState(() => value = value + step),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(
                      label: const Text('Reset'),
                      onPressed: () => setState(() => value = 0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<double> _steps(HabitType type, Habit h) => switch (type) {
        HabitType.duration => [5, 15, 30],
        HabitType.percent => [10, 25],
        _ => h.targetValue >= 10 ? [1, 5] : [0.5, 1],
      };
}
