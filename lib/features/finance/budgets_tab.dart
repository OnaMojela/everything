import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

class BudgetsTab extends ConsumerWidget {
  const BudgetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const [];
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
    final cats = {
      for (final c in ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        c.id: c
    };
    final theme = Theme.of(context);

    if (budgets.isEmpty) {
      return EmptyState(
        icon: Icons.donut_small_rounded,
        title: 'No budgets yet',
        subtitle:
            'Set weekly, monthly or yearly limits — overall, per category or per account.',
        actionLabel: 'New budget',
        onAction: () => showAppSheet(context, const BudgetEditorSheet()),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        for (final b in budgets)
          Builder(builder: (context) {
            final spent = budgetSpent(b, txs, mondayStart: settings.weekStartsMonday);
            final progress = b.amount <= 0 ? 0.0 : spent / b.amount;
            final left = b.amount - spent;
            final cat = cats[b.categoryId];
            final window = budgetWindow(b, today, mondayStart: settings.weekStartsMonday);
            final daysLeft = window.end.difference(today).inDays + 1;
            final color = cat != null ? Color(cat.colorValue) : theme.colorScheme.primary;

            return Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s12),
              child: AppCard(
                onTap: () => showAppSheet(context, BudgetEditorSheet(existing: b)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconBadge(
                          icon: cat != null
                              ? appIcon(cat.iconCode)
                              : Icons.donut_small_rounded,
                          color: color,
                          size: 40,
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
                                '${BudgetPeriod.values[b.period].label} · $daysLeft days left',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatMoney(left.abs(), settings.currencySymbol),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: left < 0 ? theme.colorScheme.error : null,
                              ),
                            ),
                            Text(left < 0 ? 'over budget' : 'left',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: left < 0
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.s12),
                    ProgressBar(progress: progress, color: color),
                    const SizedBox(height: 6),
                    Text(
                      '${formatMoney(spent, settings.currencySymbol)} of ${formatMoney(b.amount, settings.currencySymbol)} · ${(progress * 100).round()}%',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class BudgetEditorSheet extends ConsumerStatefulWidget {
  final Budget? existing;
  const BudgetEditorSheet({super.key, this.existing});

  @override
  ConsumerState<BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<BudgetEditorSheet> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final amount = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.amount));
  late BudgetPeriod period = widget.existing != null
      ? BudgetPeriod.values[widget.existing!.period]
      : BudgetPeriod.monthly;
  String? categoryId;
  String? accountId;
  DateTime? customStart;
  DateTime? customEnd;

  @override
  void initState() {
    super.initState();
    categoryId = widget.existing?.categoryId;
    accountId = widget.existing?.accountId;
    customStart = widget.existing?.customStart != null
        ? parseDayKey(widget.existing!.customStart!)
        : null;
    customEnd = widget.existing?.customEnd != null
        ? parseDayKey(widget.existing!.customEnd!)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        .where((c) => !c.isIncome)
        .toList();
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    return SheetScaffold(
      title: widget.existing == null ? 'New budget' : 'Edit budget',
      actionLabel: widget.existing == null ? 'Create budget' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'budget')) {
                  await ref.read(repoProvider).deleteBudget(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        TextField(
          controller: name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Limit'),
        ),
        const SizedBox(height: Tokens.s16),
        Text('Period', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          children: [
            for (final p in BudgetPeriod.values)
              ChoiceChip(
                label: Text(p.label),
                selected: period == p,
                onSelected: (_) => setState(() => period = p),
              ),
          ],
        ),
        if (period == BudgetPeriod.custom) ...[
          const SizedBox(height: Tokens.s12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: customStart ?? today,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100));
                    if (d != null) setState(() => customStart = dateOnly(d));
                  },
                  child: Text(customStart == null ? 'Start' : formatDay(customStart!)),
                ),
              ),
              const SizedBox(width: Tokens.s8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: customEnd ?? today,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100));
                    if (d != null) setState(() => customEnd = dateOnly(d));
                  },
                  child: Text(customEnd == null ? 'End' : formatDay(customEnd!)),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Tokens.s16),
        Text('Scope', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s4),
        Text('Leave empty to track all spending.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          runSpacing: Tokens.s8,
          children: [
            ChoiceChip(
              label: const Text('All categories'),
              selected: categoryId == null,
              onSelected: (_) => setState(() => categoryId = null),
            ),
            for (final c in categories)
              ChoiceChip(
                avatar: Icon(appIcon(c.iconCode),
                    size: 16, color: Color(c.colorValue)),
                label: Text(c.name),
                selected: categoryId == c.id,
                onSelected: (_) => setState(() => categoryId = c.id),
              ),
          ],
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: Tokens.s12),
          DropdownMenu<String?>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Account (optional)'),
            initialSelection: accountId,
            dropdownMenuEntries: [
              const DropdownMenuEntry<String?>(value: null, label: 'All accounts'),
              for (final a in accounts)
                DropdownMenuEntry<String?>(value: a.id, label: a.name),
            ],
            onSelected: (v) => setState(() => accountId = v),
          ),
        ],
        if (widget.existing != null &&
            BudgetPeriod.values[widget.existing!.period] != BudgetPeriod.custom) ...[
          const SizedBox(height: Tokens.s20),
          Text('Recent periods', style: theme.textTheme.titleSmall),
          const SizedBox(height: Tokens.s8),
          _BudgetHistory(budget: widget.existing!),
        ],
      ],
    );
  }

  Future<void> _save() async {
    final amt = parseMoneyToCents(amount.text);
    if (name.text.trim().isEmpty || amt == null || amt <= 0) return;
    final db = ref.read(dbProvider);
    final companion = BudgetsCompanion(
      name: Value(name.text.trim()),
      amount: Value(amt),
      period: Value(period.index),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      customStart: Value(customStart == null ? null : dayKey(customStart!)),
      customEnd: Value(customEnd == null ? null : dayKey(customEnd!)),
    );
    if (widget.existing == null) {
      await db.into(db.budgets).insert(companion.copyWith(
          id: Value(newId()),
          sortOrder: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000)));
    } else {
      await (db.update(db.budgets)..where((b) => b.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }
}

/// Spend vs limit for the last six periods of a weekly/monthly/yearly budget.
class _BudgetHistory extends ConsumerWidget {
  final Budget budget;
  const _BudgetHistory({required this.budget});

  DateTime _shift(DateTime ref, int periodsBack) =>
      switch (BudgetPeriod.values[budget.period]) {
        BudgetPeriod.weekly => ref.subtract(Duration(days: 7 * periodsBack)),
        BudgetPeriod.monthly => DateTime(ref.year, ref.month - periodsBack, 1),
        BudgetPeriod.yearly => DateTime(ref.year - periodsBack, 1, 1),
        BudgetPeriod.custom => ref,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];

    return Column(
      children: [
        for (var i = 0; i < 6; i++)
          Builder(builder: (context) {
            final refDate = _shift(today, i);
            final w = budgetWindow(budget, refDate,
                mondayStart: settings.weekStartsMonday);
            var spent = 0;
            for (final t in txs) {
              final type = TxType.values[t.txType];
              if (type != TxType.expense && type != TxType.investment) continue;
              if (budget.categoryId != null && t.categoryId != budget.categoryId) {
                continue;
              }
              if (budget.accountId != null && t.accountId != budget.accountId) {
                continue;
              }
              final d = parseDayKey(t.day);
              if (d.isBefore(w.start) || d.isAfter(w.end)) continue;
              spent += t.amount;
            }
            final progress = budget.amount <= 0 ? 0.0 : spent / budget.amount;
            final label = switch (BudgetPeriod.values[budget.period]) {
              BudgetPeriod.weekly => formatDay(w.start),
              BudgetPeriod.monthly => formatMonth(w.start),
              _ => '${w.start.year}',
            };
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: ProgressBar(
                      progress: progress,
                      color: theme.colorScheme.primary,
                      height: 6,
                    ),
                  ),
                  const SizedBox(width: Tokens.s8),
                  SizedBox(
                    width: 80,
                    child: Text(
                      formatMoney(spent, settings.currencySymbol),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: progress > 1
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
