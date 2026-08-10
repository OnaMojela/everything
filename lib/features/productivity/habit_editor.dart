import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

class HabitEditorSheet extends ConsumerStatefulWidget {
  final Habit? existing;
  const HabitEditorSheet({super.key, this.existing});

  @override
  ConsumerState<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends ConsumerState<HabitEditorSheet> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final description = TextEditingController(text: widget.existing?.description ?? '');
  late final unitCtrl = TextEditingController(text: widget.existing?.unit ?? '');
  late final targetCtrl =
      TextEditingController(text: trimNum(widget.existing?.targetValue ?? 1));
  late final everyNCtrl = TextEditingController(text: '${widget.existing?.everyN ?? 2}');

  late IconData icon = widget.existing != null
      ? appIcon(widget.existing!.iconCode)
      : Icons.star_rounded;
  late Color color =
      widget.existing != null ? Color(widget.existing!.colorValue) : itemColors.first;
  late HabitType type =
      widget.existing != null ? HabitType.values[widget.existing!.habitType] : HabitType.check;
  late ScheduleType schedule = widget.existing != null
      ? ScheduleType.values[widget.existing!.scheduleType]
      : ScheduleType.daily;
  late Set<int> weekdays = widget.existing == null || widget.existing!.daysOfWeek.isEmpty
      ? {1, 2, 3, 4, 5}
      : widget.existing!.daysOfWeek.split(',').map(int.parse).toSet();
  late Set<int> monthDays = widget.existing == null || widget.existing!.monthlyDays.isEmpty
      ? {1}
      : widget.existing!.monthlyDays.split(',').map(int.parse).toSet();
  TimeOfDay? reminder;

  @override
  void initState() {
    super.initState();
    final r = widget.existing?.reminderTime;
    if (r != null && r.contains(':')) {
      final parts = r.split(':');
      reminder = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetScaffold(
      title: widget.existing == null ? 'New habit' : 'Edit habit',
      actionLabel: widget.existing == null ? 'Create habit' : 'Save changes',
      onAction: _save,
      children: [
        TextField(
          controller: title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: description,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),
        const SizedBox(height: Tokens.s20),
        Text('Color', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
        const SizedBox(height: Tokens.s20),
        Text('Icon', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        IconPickerGrid(
            selected: icon, color: color, onChanged: (i) => setState(() => icon = i)),
        const SizedBox(height: Tokens.s20),
        Text('How do you complete it?', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          runSpacing: Tokens.s8,
          children: [
            for (final t in HabitType.values)
              ChoiceChip(
                avatar: Icon(t.icon, size: 16),
                label: Text(t.label),
                selected: type == t,
                onSelected: (_) => setState(() => type = t),
              ),
          ],
        ),
        if (type != HabitType.check) ...[
          const SizedBox(height: Tokens.s12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: targetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: switch (type) {
                      HabitType.duration => 'Goal (minutes)',
                      HabitType.percent => 'Goal (%)',
                      _ => 'Daily goal',
                    },
                  ),
                ),
              ),
              if (type == HabitType.numeric || type == HabitType.counter) ...[
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: TextField(
                    controller: unitCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Unit (L, pages, …)'),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: Tokens.s20),
        Text('Repeats', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          runSpacing: Tokens.s8,
          children: [
            for (final s in ScheduleType.values)
              ChoiceChip(
                label: Text(s.label),
                selected: schedule == s,
                onSelected: (_) => setState(() => schedule = s),
              ),
          ],
        ),
        if (schedule == ScheduleType.customDays) ...[
          const SizedBox(height: Tokens.s12),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d - 1]),
                  selected: weekdays.contains(d),
                  showCheckmark: false,
                  onSelected: (v) => setState(() {
                    v ? weekdays.add(d) : weekdays.remove(d);
                    if (weekdays.isEmpty) weekdays.add(d);
                  }),
                ),
            ],
          ),
        ],
        if (schedule == ScheduleType.everyN) ...[
          const SizedBox(height: Tokens.s12),
          TextField(
            controller: everyNCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Every how many days?'),
          ),
        ],
        if (schedule == ScheduleType.timesPerWeek) ...[
          const SizedBox(height: Tokens.s12),
          TextField(
            controller: everyNCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'How many times per week?',
                helperText: 'Any days you like — streaks count in weeks'),
          ),
        ],
        if (schedule == ScheduleType.monthlyDays) ...[
          const SizedBox(height: Tokens.s12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 31; d++)
                FilterChip(
                  label: Text('$d'),
                  selected: monthDays.contains(d),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setState(() {
                    v ? monthDays.add(d) : monthDays.remove(d);
                    if (monthDays.isEmpty) monthDays.add(d);
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: Tokens.s20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Reminder'),
          subtitle: Text(reminder == null ? 'Off' : reminder!.format(context)),
          trailing: reminder != null
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => reminder = null))
              : null,
          onTap: () async {
            final t = await showTimePicker(
                context: context, initialTime: reminder ?? const TimeOfDay(hour: 9, minute: 0));
            if (t != null) setState(() => reminder = t);
          },
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) return;
    final db = ref.read(dbProvider);
    final target = double.tryParse(targetCtrl.text.replaceAll(',', '.')) ?? 1;
    final companion = HabitsCompanion(
      title: Value(title.text.trim()),
      description: Value(description.text.trim()),
      iconCode: Value(icon.codePoint),
      colorValue: Value(color.toARGB32()),
      habitType: Value(type.index),
      targetValue: Value(type == HabitType.check ? 1 : target),
      unit: Value(unitCtrl.text.trim()),
      scheduleType: Value(schedule.index),
      daysOfWeek: Value((weekdays.toList()..sort()).join(',')),
      monthlyDays: Value((monthDays.toList()..sort()).join(',')),
      everyN: Value(int.tryParse(everyNCtrl.text) ?? 2),
      reminderTime: Value(reminder == null
          ? null
          : '${reminder!.hour.toString().padLeft(2, '0')}:${reminder!.minute.toString().padLeft(2, '0')}'),
    );
    if (widget.existing == null) {
      await db.into(db.habits).insert(companion.copyWith(
            id: Value(newId()),
            anchorDate: Value(dayKey(today)),
            createdAt: Value(DateTime.now()),
          ));
    } else {
      await (db.update(db.habits)..where((h) => h.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }
}
