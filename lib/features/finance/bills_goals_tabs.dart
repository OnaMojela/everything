import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

// ---------------------------------------------------------------------------
// Bills
// ---------------------------------------------------------------------------

class BillsTab extends ConsumerWidget {
  const BillsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final bills = ref.watch(billsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    if (bills.isEmpty) {
      return EmptyState(
        icon: Icons.event_repeat_rounded,
        title: 'No recurring bills',
        subtitle:
            'Track rent, subscriptions and utilities. Mark them paid and the next due date advances automatically.',
        actionLabel: 'New bill',
        onAction: () => showAppSheet(context, const BillEditorSheet()),
      );
    }

    final monthlyTotal = bills
        .fold<double>(
            0,
            (s, b) =>
                s +
                switch (BillRecurrence.values[b.recurrence]) {
                  BillRecurrence.weekly => b.amount * 52 / 12,
                  BillRecurrence.monthly => b.amount.toDouble(),
                  BillRecurrence.yearly => b.amount / 12,
                })
        .round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recurring cost',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    Text(
                        '${formatMoney(monthlyTotal, settings.currencySymbol)} / month',
                        style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              IconBadge(
                  icon: Icons.event_repeat_rounded,
                  color: theme.colorScheme.primary,
                  size: 44),
            ],
          ),
        ),
        const SectionHeader('Upcoming'),
        for (final b in bills)
          Builder(builder: (context) {
            final due = parseDayKey(b.nextDue);
            final overdue = due.isBefore(today);
            final dueToday = dayKey(due) == dayKey(today);
            return Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s8),
              child: AppCard(
                onTap: () => showAppSheet(context, BillEditorSheet(existing: b)),
                child: Row(
                  children: [
                    IconBadge(
                      icon: Icons.receipt_rounded,
                      color: overdue
                          ? theme.colorScheme.error
                          : dueToday
                              ? const Color(0xFFDB8B00)
                              : theme.colorScheme.primary,
                      size: 44,
                    ),
                    const SizedBox(width: Tokens.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            '${BillRecurrence.values[b.recurrence].label} · due ${formatDay(due)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: overdue
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatMoney(b.amount, settings.currencySymbol),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        TextButton(
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero),
                          onPressed: () async {
                            await ref.read(repoProvider).payBill(b,
                                recordTransaction: b.accountId != null);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('${b.name} marked as paid')));
                            }
                          },
                          child: const Text('Mark paid'),
                        ),
                      ],
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

class BillEditorSheet extends ConsumerStatefulWidget {
  final Bill? existing;
  const BillEditorSheet({super.key, this.existing});

  @override
  ConsumerState<BillEditorSheet> createState() => _BillEditorSheetState();
}

class _BillEditorSheetState extends ConsumerState<BillEditorSheet> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final amount = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.amount));
  late BillRecurrence recurrence = widget.existing != null
      ? BillRecurrence.values[widget.existing!.recurrence]
      : BillRecurrence.monthly;
  late DateTime nextDue =
      widget.existing != null ? parseDayKey(widget.existing!.nextDue) : today;
  String? accountId;
  String? categoryId;

  @override
  void initState() {
    super.initState();
    accountId = widget.existing?.accountId;
    categoryId = widget.existing?.categoryId;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        .where((c) => !c.isIncome)
        .toList();

    return SheetScaffold(
      title: widget.existing == null ? 'New bill' : 'Edit bill',
      actionLabel: widget.existing == null ? 'Create bill' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'bill')) {
                  await ref.read(repoProvider).deleteBill(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        TextField(
          controller: name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name (Rent, Netflix…)'),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: Tokens.s16),
        Wrap(
          spacing: Tokens.s8,
          children: [
            for (final r in BillRecurrence.values)
              ChoiceChip(
                label: Text(r.label),
                selected: recurrence == r,
                onSelected: (_) => setState(() => recurrence = r),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text('Next due ${formatDay(nextDue)}'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: nextDue,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100));
            if (d != null) setState(() => nextDue = dateOnly(d));
          },
        ),
        const SizedBox(height: Tokens.s12),
        DropdownMenu<String?>(
          expandedInsets: EdgeInsets.zero,
          label: const Text('Pay from account (optional)'),
          initialSelection: accountId,
          dropdownMenuEntries: [
            const DropdownMenuEntry<String?>(value: null, label: 'None'),
            for (final a in accounts)
              DropdownMenuEntry<String?>(value: a.id, label: a.name),
          ],
          onSelected: (v) => setState(() => accountId = v),
        ),
        const SizedBox(height: Tokens.s12),
        DropdownMenu<String?>(
          expandedInsets: EdgeInsets.zero,
          label: const Text('Category (optional)'),
          initialSelection: categoryId,
          dropdownMenuEntries: [
            const DropdownMenuEntry<String?>(value: null, label: 'None'),
            for (final c in categories)
              DropdownMenuEntry<String?>(value: c.id, label: c.name),
          ],
          onSelected: (v) => setState(() => categoryId = v),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final amt = parseMoneyToCents(amount.text);
    if (name.text.trim().isEmpty || amt == null || amt <= 0) return;
    final db = ref.read(dbProvider);
    final companion = BillsCompanion(
      name: Value(name.text.trim()),
      amount: Value(amt),
      recurrence: Value(recurrence.index),
      nextDue: Value(dayKey(nextDue)),
      accountId: Value(accountId),
      categoryId: Value(categoryId),
    );
    if (widget.existing == null) {
      await db.into(db.bills).insert(companion.copyWith(id: Value(newId())));
    } else {
      await (db.update(db.bills)..where((b) => b.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

class GoalsTab extends ConsumerWidget {
  const GoalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final goals = ref.watch(goalsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    if (goals.isEmpty) {
      return EmptyState(
        icon: Icons.flag_circle_rounded,
        title: 'No savings goals',
        subtitle:
            'Save toward an emergency fund, a trip, a laptop — anything that matters to you.',
        actionLabel: 'New goal',
        onAction: () => showAppSheet(context, const GoalEditorSheet()),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        for (final g in goals)
          Builder(builder: (context) {
            final progress = g.targetAmount <= 0 ? 0.0 : g.savedAmount / g.targetAmount;
            final remaining =
                g.targetAmount > g.savedAmount ? g.targetAmount - g.savedAmount : 0;
            final color = Color(g.colorValue);
            return Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s12),
              child: AppCard(
                onTap: () => showAppSheet(context, GoalEditorSheet(existing: g)),
                child: Row(
                  children: [
                    ProgressRing(
                      progress: progress,
                      color: color,
                      size: 64,
                      strokeWidth: 6,
                      center: Icon(appIcon(g.iconCode),
                          color: color, size: 24),
                    ),
                    const SizedBox(width: Tokens.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.name,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            '${formatMoney(g.savedAmount, settings.currencySymbol)} of ${formatMoney(g.targetAmount, settings.currencySymbol)}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          if (g.targetDay != null)
                            Text(
                              '${formatMoney(remaining, settings.currencySymbol)} to go · by ${formatDay(parseDayKey(g.targetDay!))}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _addFunds(context, ref, g, settings.currencySymbol),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _addFunds(BuildContext context, WidgetRef ref, Goal g, String symbol) {
    final ctrl = TextEditingController();
    showAppSheet(
      context,
      SheetScaffold(
        title: 'Add to ${g.name}',
        actionLabel: 'Add funds',
        onAction: () async {
          final amt = parseMoneyToCents(ctrl.text);
          if (amt == null || amt <= 0) return;
          await ref.read(repoProvider).addToGoal(g, amt);
          if (context.mounted) Navigator.pop(context);
        },
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount ($symbol)'),
          ),
        ],
      ),
    );
  }
}

class GoalEditorSheet extends ConsumerStatefulWidget {
  final Goal? existing;
  const GoalEditorSheet({super.key, this.existing});

  @override
  ConsumerState<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<GoalEditorSheet> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final target = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.targetAmount));
  late final saved = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.savedAmount));
  late Color color =
      widget.existing != null ? Color(widget.existing!.colorValue) : itemColors[4];
  late IconData icon = widget.existing != null
      ? appIcon(widget.existing!.iconCode)
      : Icons.savings_rounded;
  DateTime? targetDay;

  @override
  void initState() {
    super.initState();
    targetDay = widget.existing?.targetDay != null
        ? parseDayKey(widget.existing!.targetDay!)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.existing == null ? 'New goal' : 'Edit goal',
      actionLabel: widget.existing == null ? 'Create goal' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'goal')) {
                  await ref.read(repoProvider).deleteGoal(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        TextField(
          controller: name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Goal (Emergency fund, Japan trip…)'),
        ),
        const SizedBox(height: Tokens.s12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Target amount'),
              ),
            ),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: TextField(
                controller: saved,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Already saved'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(targetDay == null
              ? 'Target date (optional)'
              : 'By ${formatDay(targetDay!)}'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: targetDay ?? today.add(const Duration(days: 180)),
                firstDate: today,
                lastDate: DateTime(2100));
            if (d != null) setState(() => targetDay = dateOnly(d));
          },
        ),
        const SizedBox(height: Tokens.s16),
        ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
        const SizedBox(height: Tokens.s16),
        IconPickerGrid(
            selected: icon, color: color, onChanged: (i) => setState(() => icon = i)),
      ],
    );
  }

  Future<void> _save() async {
    final tgt = parseMoneyToCents(target.text);
    if (name.text.trim().isEmpty || tgt == null || tgt <= 0) return;
    final db = ref.read(dbProvider);
    final companion = GoalsCompanion(
      name: Value(name.text.trim()),
      iconCode: Value(icon.codePoint),
      colorValue: Value(color.toARGB32()),
      targetAmount: Value(tgt),
      savedAmount: Value(parseMoneyToCents(saved.text) ?? 0),
      targetDay: Value(targetDay == null ? null : dayKey(targetDay!)),
    );
    if (widget.existing == null) {
      await db.into(db.goals).insert(companion.copyWith(id: Value(newId())));
    } else {
      await (db.update(db.goals)..where((g) => g.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }
}
