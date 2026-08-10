import 'package:collection/collection.dart';
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

/// Lists standing orders and lets the user add, edit, pause or delete them.
class RecurringSheet extends ConsumerWidget {
  const RecurringSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final recurring = ref.watch(recurringTransactionsProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return SheetScaffold(
      title: 'Recurring transactions',
      actionLabel: 'New recurring transaction',
      onAction: () =>
          showAppSheet(context, const RecurringEditorSheet()),
      children: [
        Text(
          'Salary, rent, subscriptions — posted automatically on schedule.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Tokens.s12),
        if (recurring.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Tokens.s16),
            child: Text('Nothing recurring yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        for (final r in recurring)
          Builder(builder: (context) {
            final type = TxType.values[r.txType];
            final account = accounts.where((a) => a.id == r.accountId).firstOrNull;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconBadge(
                icon: type == TxType.income
                    ? Icons.arrow_downward_rounded
                    : type == TxType.transfer
                        ? Icons.swap_horiz_rounded
                        : Icons.arrow_upward_rounded,
                color: r.active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 40,
              ),
              title: Text(r.description.isEmpty ? type.label : r.description),
              subtitle: Text(
                '${BillRecurrence.values[r.recurrence].label} · '
                '${account?.name ?? '?'} · next ${formatDay(parseDayKey(r.nextRun))}'
                '${r.active ? '' : ' · paused'}',
              ),
              trailing: Text(
                formatMoney(type.sign() * r.amount, settings.currencySymbol, signed: true),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              onTap: () =>
                  showAppSheet(context, RecurringEditorSheet(existing: r)),
            );
          }),
      ],
    );
  }
}

class RecurringEditorSheet extends ConsumerStatefulWidget {
  final RecurringTransaction? existing;
  const RecurringEditorSheet({super.key, this.existing});

  @override
  ConsumerState<RecurringEditorSheet> createState() => _RecurringEditorSheetState();
}

class _RecurringEditorSheetState extends ConsumerState<RecurringEditorSheet> {
  late final amount = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.amount));
  late final description =
      TextEditingController(text: widget.existing?.description ?? '');
  late TxType type =
      widget.existing != null ? TxType.values[widget.existing!.txType] : TxType.expense;
  late BillRecurrence recurrence = widget.existing != null
      ? BillRecurrence.values[widget.existing!.recurrence]
      : BillRecurrence.monthly;
  late DateTime nextRun =
      widget.existing != null ? parseDayKey(widget.existing!.nextRun) : today;
  late bool active = widget.existing?.active ?? true;
  String? accountId;
  String? toAccountId;
  String? categoryId;

  @override
  void initState() {
    super.initState();
    accountId = widget.existing?.accountId;
    toAccountId = widget.existing?.toAccountId;
    categoryId = widget.existing?.categoryId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        .where((c) => type == TxType.income ? c.isIncome : !c.isIncome)
        .toList();
    accountId ??= accounts.firstOrNull?.id;

    return SheetScaffold(
      title: widget.existing == null ? 'New recurring' : 'Edit recurring',
      actionLabel: widget.existing == null ? 'Create' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'recurring transaction')) {
                  await ref.read(repoProvider).deleteRecurring(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        SegmentedButton<TxType>(
          showSelectedIcon: false,
          segments: [
            for (final t in [TxType.expense, TxType.income, TxType.transfer])
              ButtonSegment(value: t, label: Text(t.label)),
          ],
          selected: {type},
          onSelectionChanged: (s) => setState(() {
            type = s.first;
            categoryId = null;
          }),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: amount,
          autofocus: widget.existing == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: description,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description (Salary, Rent…)'),
        ),
        const SizedBox(height: Tokens.s12),
        DropdownMenu<String>(
          expandedInsets: EdgeInsets.zero,
          label: Text(type == TxType.transfer ? 'From account' : 'Account'),
          initialSelection: accountId,
          dropdownMenuEntries: [
            for (final a in accounts) DropdownMenuEntry(value: a.id, label: a.name),
          ],
          onSelected: (v) => setState(() => accountId = v),
        ),
        if (type == TxType.transfer) ...[
          const SizedBox(height: Tokens.s12),
          DropdownMenu<String>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('To account'),
            initialSelection: toAccountId,
            dropdownMenuEntries: [
              for (final a in accounts.where((a) => a.id != accountId))
                DropdownMenuEntry(value: a.id, label: a.name),
            ],
            onSelected: (v) => setState(() => toAccountId = v),
          ),
        ] else if (categories.isNotEmpty) ...[
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
        const SizedBox(height: Tokens.s16),
        Text('Repeats', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
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
          label: Text('Next run ${formatDay(nextRun)}'),
          onPressed: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: nextRun,
                firstDate: today,
                lastDate: DateTime(2100));
            if (d != null) setState(() => nextRun = dateOnly(d));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Paused orders keep their schedule but never post'),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final amt = parseMoneyToCents(amount.text);
    if (amt == null || amt <= 0 || accountId == null) return;
    if (type == TxType.transfer && toAccountId == null) return;
    final db = ref.read(dbProvider);
    final companion = RecurringTransactionsCompanion(
      txType: Value(type.index),
      amount: Value(amt),
      accountId: Value(accountId!),
      toAccountId: Value(type == TxType.transfer ? toAccountId : null),
      categoryId: Value(type == TxType.transfer ? null : categoryId),
      description: Value(description.text.trim()),
      recurrence: Value(recurrence.index),
      nextRun: Value(dayKey(nextRun)),
      active: Value(active),
    );
    if (widget.existing == null) {
      await db
          .into(db.recurringTransactions)
          .insert(companion.copyWith(id: Value(newId())));
    } else {
      await (db.update(db.recurringTransactions)
            ..where((r) => r.id.equals(widget.existing!.id)))
          .write(companion);
    }
    // Post immediately if the first run is already due.
    await ref.read(repoProvider).postDueRecurringTransactions();
    if (mounted) Navigator.pop(context);
  }
}
