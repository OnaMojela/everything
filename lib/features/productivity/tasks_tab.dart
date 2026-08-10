import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

class TasksTab extends ConsumerWidget {
  const TasksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const [];
    final open = tasks.where((t) => !t.completed).toList();
    final done = tasks.where((t) => t.completed).toList()
      ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

    final todayK = dayKey(today);
    final todayTasks =
        open.where((t) => t.dueDay == todayK || t.dueDay == null).toList();
    final upcoming = open.where((t) => t.dueDay != null && t.dueDay!.compareTo(todayK) > 0).toList();

    if (tasks.isEmpty) {
      return EmptyState(
        icon: Icons.task_alt_rounded,
        title: 'No tasks yet',
        subtitle:
            'Capture one-time to-dos here. Unfinished tasks roll over to the next day automatically.',
        actionLabel: 'Add task',
        onAction: () => showAppSheet(context, const TaskEditorSheet()),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        if (todayTasks.isNotEmpty) ...[
          const SectionHeader('Today'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: Tokens.s4),
            child: Column(children: [for (final t in todayTasks) TaskRow(task: t)]),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          const SectionHeader('Upcoming'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: Tokens.s4),
            child: Column(children: [for (final t in upcoming) TaskRow(task: t)]),
          ),
        ],
        if (done.isNotEmpty) ...[
          const SectionHeader('Completed'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: Tokens.s4),
            child: Column(children: [for (final t in done.take(20)) TaskRow(task: t)]),
          ),
        ],
      ],
    );
  }
}

class TaskRow extends ConsumerWidget {
  final Task task;
  const TaskRow({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtasks = ref.watch(subtasksProvider(task.id)).valueOrNull ?? const [];
    final doneSubs = subtasks.where((s) => s.done).length;
    final priority = TaskPriority.values[task.priority];

    final meta = <String>[
      if (task.dueDay != null) formatDay(parseDayKey(task.dueDay!)),
      if (task.dueTime != null) task.dueTime!,
      if (task.category.isNotEmpty) task.category,
      if (subtasks.isNotEmpty) '$doneSubs/${subtasks.length} subtasks',
      if (task.estimatedMinutes != null) '~${task.estimatedMinutes}m',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.rControl),
      onTap: () => showAppSheet(context, TaskEditorSheet(existing: task)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: task.completed,
              shape: const CircleBorder(),
              onChanged: (v) => ref.read(repoProvider).setTaskCompleted(task, v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: task.completed ? TextDecoration.lineThrough : null,
                      color: task.completed ? theme.colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (priority != TaskPriority.none)
              Padding(
                padding: const EdgeInsets.only(left: Tokens.s8),
                child: Icon(Icons.flag_rounded, size: 18, color: priority.color),
              ),
          ],
        ),
      ),
    );
  }
}

class TaskEditorSheet extends ConsumerStatefulWidget {
  final Task? existing;
  const TaskEditorSheet({super.key, this.existing});

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final note = TextEditingController(text: widget.existing?.note ?? '');
  late final category = TextEditingController(text: widget.existing?.category ?? '');
  late final tags = TextEditingController(text: widget.existing?.tags ?? '');
  late final estimate = TextEditingController(
      text: widget.existing?.estimatedMinutes?.toString() ?? '');
  late final subtaskCtrl = TextEditingController();

  late DateTime? dueDay =
      widget.existing?.dueDay != null ? parseDayKey(widget.existing!.dueDay!) : today;
  TimeOfDay? dueTime;
  late TaskPriority priority = widget.existing != null
      ? TaskPriority.values[widget.existing!.priority]
      : TaskPriority.none;

  @override
  void initState() {
    super.initState();
    final t = widget.existing?.dueTime;
    if (t != null && t.contains(':')) {
      final p = t.split(':');
      dueTime = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtasks = widget.existing == null
        ? const <Subtask>[]
        : ref.watch(subtasksProvider(widget.existing!.id)).valueOrNull ?? const [];

    return SheetScaffold(
      title: widget.existing == null ? 'New task' : 'Edit task',
      actionLabel: widget.existing == null ? 'Create task' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'task')) {
                  await ref.read(repoProvider).deleteTask(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        TextField(
          controller: title,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: note,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
        ),
        const SizedBox(height: Tokens.s12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(dueDay == null ? 'No date' : formatDay(dueDay!)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: dueDay ?? today,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => dueDay = dateOnly(d));
                },
              ),
            ),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(dueTime == null ? 'No time' : dueTime!.format(context)),
                onPressed: () async {
                  final t = await showTimePicker(
                      context: context,
                      initialTime: dueTime ?? const TimeOfDay(hour: 9, minute: 0));
                  if (t != null) setState(() => dueTime = t);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s16),
        Text('Priority', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          children: [
            for (final p in TaskPriority.values)
              ChoiceChip(
                label: Text(p.label),
                selected: priority == p,
                avatar: p == TaskPriority.none
                    ? null
                    : Icon(Icons.flag_rounded, size: 16, color: p.color),
                onSelected: (_) => setState(() => priority = p),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: TextField(
                controller: estimate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Estimate (min)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: tags,
          decoration: const InputDecoration(labelText: 'Tags (comma-separated)'),
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: Tokens.s20),
          Text('Subtasks', style: theme.textTheme.titleSmall),
          const SizedBox(height: Tokens.s4),
          for (final s in subtasks)
            Row(
              children: [
                Checkbox(
                  value: s.done,
                  shape: const CircleBorder(),
                  onChanged: (v) async {
                    final db = ref.read(dbProvider);
                    await (db.update(db.subtasks)..where((x) => x.id.equals(s.id)))
                        .write(SubtasksCompanion(done: Value(v ?? false)));
                  },
                ),
                Expanded(
                  child: Text(s.title,
                      style: s.done
                          ? theme.textTheme.bodyMedium?.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: theme.colorScheme.onSurfaceVariant)
                          : theme.textTheme.bodyMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () async {
                    final db = ref.read(dbProvider);
                    await (db.delete(db.subtasks)..where((x) => x.id.equals(s.id))).go();
                  },
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: subtaskCtrl,
                  decoration: const InputDecoration(hintText: 'Add subtask'),
                  onSubmitted: (_) => _addSubtask(),
                ),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add_rounded),
                onPressed: _addSubtask,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _addSubtask() async {
    final text = subtaskCtrl.text.trim();
    if (text.isEmpty || widget.existing == null) return;
    final db = ref.read(dbProvider);
    await db.into(db.subtasks).insert(SubtasksCompanion.insert(
          id: newId(),
          taskId: widget.existing!.id,
          title: text,
          sortOrder: Value(DateTime.now().millisecondsSinceEpoch),
        ));
    subtaskCtrl.clear();
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) return;
    final db = ref.read(dbProvider);
    final companion = TasksCompanion(
      title: Value(title.text.trim()),
      note: Value(note.text.trim()),
      dueDay: Value(dueDay == null ? null : dayKey(dueDay!)),
      dueTime: Value(dueTime == null
          ? null
          : '${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}'),
      priority: Value(priority.index),
      category: Value(category.text.trim()),
      tags: Value(tags.text.trim()),
      estimatedMinutes: Value(int.tryParse(estimate.text)),
    );
    if (widget.existing == null) {
      await db
          .into(db.tasks)
          .insert(companion.copyWith(id: Value(newId()), createdAt: Value(DateTime.now())));
    } else {
      await (db.update(db.tasks)..where((t) => t.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }
}
