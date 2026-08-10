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
import 'recurring_sheet.dart';

class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  String? filterAccountId;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final cats = {
      for (final c in ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        c.id: c
    };

    final filtered = filterAccountId == null
        ? txs
        : txs
            .where((t) =>
                t.accountId == filterAccountId || t.toAccountId == filterAccountId)
            .toList();
    final byDay = groupBy(filtered, (Transaction t) => t.day);
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    if (txs.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No transactions yet',
        subtitle: accounts.isEmpty
            ? 'Create an account first, then record income, expenses and transfers.'
            : 'Record your first income, expense or transfer.',
        actionLabel: accounts.isEmpty ? null : 'Add transaction',
        onAction: accounts.isEmpty
            ? null
            : () => showAppSheet(context, const TransactionEditorSheet()),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ActionChip(
                  avatar: const Icon(Icons.event_repeat_rounded, size: 16),
                  label: const Text('Recurring'),
                  onPressed: () => showAppSheet(context, const RecurringSheet()),
                ),
              ),
              const SizedBox(width: Tokens.s8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ChoiceChip(
                  label: const Text('All accounts'),
                  selected: filterAccountId == null,
                  onSelected: (_) => setState(() => filterAccountId = null),
                ),
              ),
              const SizedBox(width: Tokens.s8),
              for (final a in accounts)
                Padding(
                  padding: const EdgeInsets.only(right: Tokens.s8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: ChoiceChip(
                      label: Text(a.name),
                      selected: filterAccountId == a.id,
                      onSelected: (_) => setState(() => filterAccountId = a.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, 96),
            children: [
              for (final day in days) ...[
                SectionHeader(formatDay(parseDayKey(day))),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.s12, vertical: Tokens.s4),
                  child: Column(
                    children: [
                      for (final t in byDay[day]!)
                        TransactionRow(
                            tx: t,
                            category: cats[t.categoryId],
                            accounts: accounts,
                            symbol: settings.currencySymbol),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s4),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class TransactionRow extends ConsumerWidget {
  final Transaction tx;
  final Category? category;
  final List<Account> accounts;
  final String symbol;

  const TransactionRow({
    super.key,
    required this.tx,
    required this.category,
    required this.accounts,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final type = TxType.values[tx.txType];
    final account = accounts.where((a) => a.id == tx.accountId).firstOrNull;
    final toAccount = accounts.where((a) => a.id == tx.toAccountId).firstOrNull;

    final title = tx.description.isNotEmpty
        ? tx.description
        : tx.merchant.isNotEmpty
            ? tx.merchant
            : type == TxType.transfer
                ? 'Transfer'
                : category?.name ?? type.label;

    final subtitle = [
      if (type == TxType.transfer && toAccount != null)
        '${account?.name ?? '?'} → ${toAccount.name}'
      else if (account != null)
        account.name,
      if (tx.time != null) tx.time!,
      if (type == TxType.refund) 'Refund',
      if (type == TxType.investment) 'Investment',
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.rControl),
      onTap: () => showAppSheet(context, TransactionEditorSheet(existing: tx)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            IconBadge(
              icon: type == TxType.transfer
                  ? Icons.swap_horiz_rounded
                  : category != null
                      ? appIcon(category!.iconCode)
                      : type == TxType.income
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
              color: type == TxType.transfer
                  ? theme.colorScheme.primary
                  : category != null
                      ? Color(category!.colorValue)
                      : theme.colorScheme.primary,
              size: 40,
            ),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              type == TxType.transfer
                  ? formatMoney(tx.amount, symbol)
                  : formatMoney(type.sign() * tx.amount, symbol, signed: true),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: type.sign() > 0
                    ? const Color(0xFF2E9E5B)
                    : type == TxType.transfer
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionEditorSheet extends ConsumerStatefulWidget {
  final Transaction? existing;
  const TransactionEditorSheet({super.key, this.existing});

  @override
  ConsumerState<TransactionEditorSheet> createState() => _TransactionEditorSheetState();
}

class _TransactionEditorSheetState extends ConsumerState<TransactionEditorSheet> {
  late final amount = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.amount));
  late final description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final merchant = TextEditingController(text: widget.existing?.merchant ?? '');
  late final note = TextEditingController(text: widget.existing?.note ?? '');
  late final tags = TextEditingController(text: widget.existing?.tags ?? '');

  late TxType type =
      widget.existing != null ? TxType.values[widget.existing!.txType] : TxType.expense;
  String? accountId;
  String? toAccountId;
  String? categoryId;
  late DateTime day =
      widget.existing != null ? parseDayKey(widget.existing!.day) : today;
  TimeOfDay? time;

  bool _categoryAutoFilled = false;

  @override
  void initState() {
    super.initState();
    accountId = widget.existing?.accountId;
    toAccountId = widget.existing?.toAccountId;
    categoryId = widget.existing?.categoryId;
    final t = widget.existing?.time;
    if (t != null && t.contains(':')) {
      final p = t.split(':');
      time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
    // Typing a known merchant fills in the category it usually belongs to.
    merchant.addListener(_suggestCategoryFromMerchant);
  }

  @override
  void dispose() {
    merchant.removeListener(_suggestCategoryFromMerchant);
    super.dispose();
  }

  Future<void> _suggestCategoryFromMerchant() async {
    // Never override a category the user chose themselves.
    if (categoryId != null && !_categoryAutoFilled) return;
    final suggestion =
        await ref.read(repoProvider).suggestCategoryFor(merchant.text);
    if (!mounted || suggestion == null || suggestion == categoryId) return;
    setState(() {
      categoryId = suggestion;
      _categoryAutoFilled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const <Category>[])
        .where((c) => type == TxType.income || type == TxType.refund
            ? c.isIncome
            : !c.isIncome)
        .toList();
    accountId ??= accounts.firstOrNull?.id;

    return SheetScaffold(
      title: widget.existing == null ? 'New transaction' : 'Edit transaction',
      actionLabel: widget.existing == null ? 'Save transaction' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'transaction')) {
                  await ref.read(repoProvider).deleteTransaction(widget.existing!.id);
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
          selected: {
            type == TxType.refund
                ? TxType.income
                : type == TxType.investment
                    ? TxType.expense
                    : type
          },
          onSelectionChanged: (s) => setState(() {
            type = s.first;
            categoryId = null;
          }),
        ),
        const SizedBox(height: Tokens.s8),
        Row(
          children: [
            if (type == TxType.expense || type == TxType.investment)
              _subTypeChip('Investment', TxType.investment, TxType.expense),
            if (type == TxType.income || type == TxType.refund)
              _subTypeChip('Refund', TxType.refund, TxType.income),
          ],
        ),
        const SizedBox(height: Tokens.s8),
        TextField(
          controller: amount,
          autofocus: widget.existing == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: theme.textTheme.headlineMedium,
          decoration: const InputDecoration(labelText: 'Amount'),
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
        ],
        if (type != TxType.transfer) ...[
          const SizedBox(height: Tokens.s16),
          Text('Category', style: theme.textTheme.titleSmall),
          const SizedBox(height: Tokens.s8),
          Wrap(
            spacing: Tokens.s8,
            runSpacing: Tokens.s8,
            children: [
              for (final c in categories)
                ChoiceChip(
                  avatar: Icon(appIcon(c.iconCode),
                      size: 16, color: Color(c.colorValue)),
                  label: Text(c.name),
                  selected: categoryId == c.id,
                  onSelected: (_) => setState(() {
                    categoryId = c.id;
                    _categoryAutoFilled = false;
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: Tokens.s16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(formatDay(day)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100));
                  if (d != null) setState(() => day = dateOnly(d));
                },
              ),
            ),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(time == null ? 'Time' : time!.format(context)),
                onPressed: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: time ?? TimeOfDay.now());
                  if (t != null) setState(() => time = t);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
            controller: description,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: Tokens.s12),
        Row(
          children: [
            Expanded(
              child: TextField(
                  controller: merchant,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Merchant')),
            ),
            const SizedBox(width: Tokens.s12),
            Expanded(
              child: TextField(
                  controller: tags,
                  decoration: const InputDecoration(labelText: 'Tags')),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note')),
      ],
    );
  }

  Widget _subTypeChip(String label, TxType special, TxType base) {
    return FilterChip(
      label: Text(label),
      selected: type == special,
      onSelected: (v) => setState(() => type = v ? special : base),
    );
  }

  Future<void> _save() async {
    final amt = parseMoneyToCents(amount.text);
    if (amt == null || amt <= 0 || accountId == null) return;
    if (type == TxType.transfer && toAccountId == null) return;
    final db = ref.read(dbProvider);
    final companion = TransactionsCompanion(
      txType: Value(type.index),
      amount: Value(amt),
      accountId: Value(accountId!),
      toAccountId: Value(type == TxType.transfer ? toAccountId : null),
      categoryId: Value(type == TxType.transfer ? null : categoryId),
      merchant: Value(merchant.text.trim()),
      description: Value(description.text.trim()),
      note: Value(note.text.trim()),
      tags: Value(tags.text.trim()),
      day: Value(dayKey(day)),
      time: Value(time == null
          ? null
          : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'),
    );
    if (widget.existing == null) {
      await db.into(db.transactions).insert(
          companion.copyWith(id: Value(newId()), createdAt: Value(DateTime.now())));
    } else {
      await (db.update(db.transactions)
            ..where((t) => t.id.equals(widget.existing!.id)))
          .write(companion);
    }
    // Learn the merchant/category pairing for next time.
    final learnFrom =
        merchant.text.trim().isNotEmpty ? merchant.text : description.text;
    await ref.read(repoProvider).learnMerchantCategory(learnFrom, categoryId);
    if (mounted) Navigator.pop(context);
  }
}
