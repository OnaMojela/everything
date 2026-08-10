import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

enum _PlannerView { day, week, agenda }

class PlannerTab extends ConsumerStatefulWidget {
  const PlannerTab({super.key});

  @override
  ConsumerState<PlannerTab> createState() => _PlannerTabState();
}

class _PlannerTabState extends ConsumerState<PlannerTab> {
  DateTime selected = today;
  _PlannerView view = _PlannerView.day;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(formatDay(selected),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              SegmentedButton<_PlannerView>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: _PlannerView.day, label: Text('Day')),
                  ButtonSegment(value: _PlannerView.week, label: Text('Week')),
                  ButtonSegment(value: _PlannerView.agenda, label: Text('Agenda')),
                ],
                selected: {view},
                onSelectionChanged: (s) => setState(() => view = s.first),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(
                    () => selected = selected.subtract(const Duration(days: 1))),
              ),
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => selected = today),
                    child: Text(formatFullDay(selected)),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy previous day',
                icon: const Icon(Icons.content_copy_rounded, size: 20),
                onPressed: () async {
                  final from = selected.subtract(const Duration(days: 1));
                  final count = await ref
                      .read(repoProvider)
                      .copyPlannerDay(dayKey(from), dayKey(selected));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(count == 0
                            ? 'Nothing to copy from ${formatDay(from)}'
                            : 'Copied $count blocks from ${formatDay(from)}')));
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () =>
                    setState(() => selected = selected.add(const Duration(days: 1))),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (view) {
            _PlannerView.day => _DayTimeline(day: selected),
            _PlannerView.week => _WeekView(
                anchor: selected, onOpenDay: (d) => setState(() {
                      selected = d;
                      view = _PlannerView.day;
                    })),
            _PlannerView.agenda => _AgendaView(from: selected),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Day timeline
// ---------------------------------------------------------------------------

class _DayTimeline extends ConsumerWidget {
  final DateTime day;
  const _DayTimeline({required this.day});

  static const hourHeight = 64.0;
  static const startHour = 5;
  static const endHour = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(plannerEventsProvider(dayKey(day))).valueOrNull ?? const [];
    final theme = Theme.of(context);
    final totalHeight = (endHour - startHour) * hourHeight;

    // Read-only overlays: timed tasks and habit reminders for this day.
    final tasks = (ref.watch(tasksProvider).valueOrNull ?? const <Task>[])
        .where((t) => t.dueDay == dayKey(day) && t.dueTime != null && !t.completed)
        .toList();
    final habits = (ref.watch(habitsProvider).valueOrNull ?? const <Habit>[])
        .where((h) => h.reminderTime != null && habitDueOn(h, day))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, 96),
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          children: [
            for (var h = startHour; h < endHour; h++)
              Positioned(
                top: (h - startHour) * hourHeight,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
                  ],
                ),
              ),
            // task / habit overlays (visual only — behind the tap layer)
            for (final t in tasks)
              _overlayChip(
                context,
                minutes: _parseTime(t.dueTime!),
                label: t.title,
                icon: Icons.task_alt_rounded,
                color: TaskPriority.values[t.priority].color,
              ),
            for (final h in habits)
              _overlayChip(
                context,
                minutes: _parseTime(h.reminderTime!),
                label: h.title,
                icon: Icons.repeat_rounded,
                color: Color(h.colorValue),
              ),
            // tap-to-create layer
            Positioned.fill(
              left: 52,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  final minutes =
                      ((details.localPosition.dy / hourHeight) + startHour) * 60;
                  final snapped = (minutes / 30).round() * 30;
                  showAppSheet(
                    context,
                    PlannerEventSheet(day: day, initialStart: snapped),
                  );
                },
              ),
            ),
            for (final e in events)
              _DraggableEventBlock(event: e, day: day, key: ValueKey(e.id)),
            if (dayKey(day) == dayKey(today))
              Positioned(
                top: (DateTime.now().hour + DateTime.now().minute / 60 - startHour) *
                    hourHeight,
                left: 44,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: theme.colorScheme.primary, shape: BoxShape.circle),
                      ),
                      Expanded(
                          child: Container(height: 2, color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  Widget _overlayChip(BuildContext context,
      {required int minutes,
      required String label,
      required IconData icon,
      required Color color}) {
    final top = (minutes / 60 - startHour) * hourHeight;
    if (top < 0) return const SizedBox.shrink();
    return Positioned(
      top: top,
      right: 0,
      width: 132,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: .35)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A planner block: tap to edit, long-press-drag to move, drag the bottom
/// handle to resize. Everything snaps to 15 minutes.
class _DraggableEventBlock extends ConsumerStatefulWidget {
  final PlannerEvent event;
  final DateTime day;
  const _DraggableEventBlock({super.key, required this.event, required this.day});

  @override
  ConsumerState<_DraggableEventBlock> createState() => _DraggableEventBlockState();
}

class _DraggableEventBlockState extends ConsumerState<_DraggableEventBlock> {
  double _moveDy = 0;
  double _resizeDy = 0;
  bool _dragging = false;

  static const _hourHeight = _DayTimeline.hourHeight;
  static const _startHour = _DayTimeline.startHour;

  int _snap(double minutes) => ((minutes / 15).round() * 15).clamp(0, 24 * 60);

  Future<void> _commit() async {
    final e = widget.event;
    final deltaMove = _moveDy / _hourHeight * 60;
    final deltaResize = _resizeDy / _hourHeight * 60;
    var newStart = _snap(e.startMinutes + deltaMove);
    var newEnd = _snap(e.endMinutes + deltaMove + deltaResize);
    if (newEnd - newStart < 15) newEnd = newStart + 15;
    if (newEnd > 24 * 60) {
      newEnd = 24 * 60;
      newStart = newEnd - (e.endMinutes - e.startMinutes);
    }
    setState(() {
      _moveDy = 0;
      _resizeDy = 0;
      _dragging = false;
    });
    if (newStart == e.startMinutes && newEnd == e.endMinutes) return;
    final db = ref.read(dbProvider);
    await (db.update(db.plannerEvents)..where((x) => x.id.equals(e.id))).write(
        PlannerEventsCompanion(
            startMinutes: Value(newStart), endMinutes: Value(newEnd)));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final color = Color(e.colorValue);
    final top = (e.startMinutes / 60 - _startHour) * _hourHeight + _moveDy;
    final height = ((e.endMinutes - e.startMinutes) / 60 * _hourHeight + _resizeDy)
        .clamp(28.0, 2000.0);
    final recurring = e.recurrence != PlannerRecurrence.none.index;

    return Positioned(
      top: top,
      left: 52,
      right: 0,
      height: height,
      child: GestureDetector(
        onLongPressStart: (_) => setState(() => _dragging = true),
        onLongPressMoveUpdate: (d) => setState(() => _moveDy = d.offsetFromOrigin.dy),
        onLongPressEnd: (_) => _commit(),
        child: Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 2),
          child: Material(
            color: color.withValues(alpha: _dragging ? .30 : .16),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showAppSheet(
                  context, PlannerEventSheet(day: widget.day, existing: e)),
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: color, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (recurring)
                              Icon(Icons.repeat_rounded, size: 12, color: color),
                          ],
                        ),
                        Text(
                          '${formatTimeOfDayMinutes(e.startMinutes)} – ${formatTimeOfDayMinutes(e.endMinutes)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // resize handle
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 14,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => setState(() => _dragging = true),
                      onVerticalDragUpdate: (d) =>
                          setState(() => _resizeDy += d.delta.dy),
                      onVerticalDragEnd: (_) => _commit(),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week view
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerWidget {
  final DateTime anchor;
  final ValueChanged<DateTime> onOpenDay;
  const _WeekView({required this.anchor, required this.onOpenDay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = startOfWeek(anchor);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, 96),
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final d = start.add(Duration(days: i));
            final events =
                ref.watch(plannerEventsProvider(dayKey(d))).valueOrNull ?? const [];
            final isToday = dayKey(d) == dayKey(today);
            return Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s8),
              child: AppCard(
                onTap: () => onOpenDay(d),
                padding: const EdgeInsets.all(Tokens.s12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Column(
                        children: [
                          Text(
                            ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: isToday
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant),
                          ),
                          Text('${d.day}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isToday ? theme.colorScheme.primary : null)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: events.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('—',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant)),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final e in events)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                              color: Color(e.colorValue),
                                              shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(formatTimeOfDayMinutes(e.startMinutes),
                                            style: theme.textTheme.labelSmall?.copyWith(
                                                color:
                                                    theme.colorScheme.onSurfaceVariant)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(e.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Agenda view: next 14 days flat list
// ---------------------------------------------------------------------------

class _AgendaView extends ConsumerWidget {
  final DateTime from;
  const _AgendaView({required this.from});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, 96),
      children: [
        for (var i = 0; i < 14; i++)
          Builder(builder: (context) {
            final d = from.add(Duration(days: i));
            final events =
                ref.watch(plannerEventsProvider(dayKey(d))).valueOrNull ?? const [];
            if (events.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(formatDay(d)),
                AppCard(
                  padding: const EdgeInsets.all(Tokens.s12),
                  child: Column(
                    children: [
                      for (final e in events)
                        InkWell(
                          borderRadius: BorderRadius.circular(Tokens.rControl),
                          onTap: () => showAppSheet(
                              context, PlannerEventSheet(day: d, existing: e)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Color(e.colorValue),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: Tokens.s12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e.title,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(fontWeight: FontWeight.w600)),
                                      Text(
                                        '${formatTimeOfDayMinutes(e.startMinutes)} – ${formatTimeOfDayMinutes(e.endMinutes)}',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                if (e.recurrence != 0)
                                  Icon(Icons.repeat_rounded,
                                      size: 14, color: Color(e.colorValue)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s8),
              ],
            );
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Event editor
// ---------------------------------------------------------------------------

class PlannerEventSheet extends ConsumerStatefulWidget {
  final DateTime day;
  final PlannerEvent? existing;
  final int? initialStart;

  const PlannerEventSheet({super.key, required this.day, this.existing, this.initialStart});

  @override
  ConsumerState<PlannerEventSheet> createState() => _PlannerEventSheetState();
}

class _PlannerEventSheetState extends ConsumerState<PlannerEventSheet> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final note = TextEditingController(text: widget.existing?.note ?? '');
  late int start = widget.existing?.startMinutes ?? widget.initialStart ?? 9 * 60;
  late int end = widget.existing?.endMinutes ??
      ((widget.initialStart ?? 9 * 60) + 60);
  late Color color = widget.existing != null
      ? Color(widget.existing!.colorValue)
      : itemColors.first;
  late PlannerRecurrence recurrence = widget.existing != null
      ? PlannerRecurrence.values[widget.existing!.recurrence]
      : PlannerRecurrence.none;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetScaffold(
      title: widget.existing == null ? 'Plan a block' : 'Edit block',
      actionLabel: 'Save',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(repoProvider).deletePlannerEvent(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
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
        Row(
          children: [
            Expanded(child: _timeButton(context, 'Starts', start, (m) {
              setState(() {
                start = m;
                if (end <= start) end = start + 30;
              });
            })),
            const SizedBox(width: Tokens.s8),
            Expanded(child: _timeButton(context, 'Ends', end, (m) {
              setState(() => end = m > start ? m : start + 30);
            })),
          ],
        ),
        const SizedBox(height: Tokens.s16),
        Text('Repeats', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          children: [
            for (final r in PlannerRecurrence.values)
              ChoiceChip(
                label: Text(r == PlannerRecurrence.weekly
                    ? 'Weekly on ${formatFullDay(widget.day).split(',').first}s'
                    : r.label),
                selected: recurrence == r,
                onSelected: (_) => setState(() => recurrence = r),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s16),
        ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
      ],
    );
  }

  Widget _timeButton(
      BuildContext context, String label, int minutes, ValueChanged<int> onPicked) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.schedule_rounded, size: 18),
      label: Text('$label ${formatTimeOfDayMinutes(minutes)}'),
      onPressed: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (t != null) onPicked(t.hour * 60 + t.minute);
      },
    );
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) return;
    final db = ref.read(dbProvider);
    if (widget.existing == null) {
      await db.into(db.plannerEvents).insert(PlannerEventsCompanion.insert(
            id: newId(),
            title: title.text.trim(),
            day: dayKey(widget.day),
            startMinutes: start,
            endMinutes: end,
            colorValue: color.toARGB32(),
            note: Value(note.text.trim()),
            recurrence: Value(recurrence.index),
          ));
    } else {
      await (db.update(db.plannerEvents)
            ..where((e) => e.id.equals(widget.existing!.id)))
          .write(PlannerEventsCompanion(
        title: Value(title.text.trim()),
        startMinutes: Value(start),
        endMinutes: Value(end),
        colorValue: Value(color.toARGB32()),
        note: Value(note.text.trim()),
        recurrence: Value(recurrence.index),
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}
