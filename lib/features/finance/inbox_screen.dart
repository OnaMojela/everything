import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/notification_capture.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/bank_parser.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/logic/duplicate_detection.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';

/// Review queue for transactions detected in bank notifications. Nothing is
/// added to the ledger until the user confirms it here.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final items = ref.watch(inboxItemsProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final pending =
        items.where((i) => i.status == InboxStatus.pending.index).toList();
    // Duplicates are folded into the item they repeat, so they never appear
    // as separate rows.
    final duplicateCount =
        items.where((i) => i.status == InboxStatus.duplicate.index).length;
    final reviewed = items
        .where((i) =>
            i.status == InboxStatus.confirmed.index ||
            i.status == InboxStatus.ignored.index)
        .take(20)
        .toList();

    // Pull anything new the listener captured while we were away.
    ref.watch(captureRefreshProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction inbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Check for new',
            onPressed: () async {
              final count = await ref
                  .read(notificationCaptureProvider)
                  .drainAndFile(autoConfirmHighConfidence: settings.captureAutoConfirm);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(count == 0
                      ? 'Nothing new captured'
                      : 'Captured $count new ${count == 1 ? 'notification' : 'notifications'}'),
                ));
              }
            },
          ),
          if (reviewed.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: 'Clear reviewed',
              onPressed: () =>
                  ref.read(notificationCaptureProvider).clearReviewed(),
            ),
        ],
      ),
      body: !settings.captureEnabled
          ? EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'Transaction capture is off',
              subtitle:
                  'Turn it on in Settings and Everything will read your bank notifications '
                  'to suggest transactions — you always confirm before anything is saved.',
            )
          : items.isEmpty
              ? EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'Nothing captured yet',
                  subtitle:
                      'When your bank sends a notification about money leaving or entering '
                      'your account, it will appear here for review.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s24),
                  children: [
                    // Without the user's own digits every account number in a
                    // message is ambiguous, so nothing can be told apart.
                    if (pending.isNotEmpty &&
                        accounts.isNotEmpty &&
                        NotificationCaptureService.ownAccountDigits(accounts)
                            .isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Tokens.s12),
                        child: AppCard(
                          child: Row(
                            children: [
                              Icon(Icons.tips_and_updates_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: Tokens.s12),
                              Expanded(
                                child: Text(
                                  'Add the last 4 digits of your accounts under '
                                  'Finance → Accounts. Until then, a payment to '
                                  'someone else’s account looks the same as money '
                                  'arriving in yours.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (pending.isNotEmpty) ...[
                      SectionHeader('Needs review · ${pending.length}'),
                      for (final item in pending)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Tokens.s12),
                          child: _InboxCard(item: item, accounts: accounts),
                        ),
                    ],
                    if (duplicateCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: Tokens.s8),
                        child: Row(
                          children: [
                            Icon(Icons.merge_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$duplicateCount repeat ${duplicateCount == 1 ? 'notification' : 'notifications'} '
                                'merged automatically',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (reviewed.isNotEmpty) ...[
                      const SectionHeader('Reviewed'),
                      AppCard(
                        padding: const EdgeInsets.all(Tokens.s8),
                        child: Column(
                          children: [
                            for (final item in reviewed)
                              _ReviewedRow(item: item, accounts: accounts),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _InboxCard extends ConsumerWidget {
  final InboxItem item;
  final List<Account> accounts;

  const _InboxCard({required this.item, required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final matched =
        accounts.where((a) => a.id == item.matchedAccountId).firstOrNull;
    // Re-read the message against the accounts as they stand now, so adding
    // your card digits fixes the older items sitting in the queue too.
    final reading = resolveOwnership(
      Dedupe.reparse(item),
      NotificationCaptureService.ownAccountDigits(accounts),
    );
    final type = reading.type ??
        (item.txType != null ? TxType.values[item.txType!] : TxType.expense);
    final isCredit = type.sign() > 0;
    final notYours = reading.ownership == Ownership.someoneElse;
    final lowConfidence = item.confidence < 0.6 && !notYours;
    // Prefer the freshly read figure: anything captured before a parser fix
    // still holds whatever was stored at the time.
    final reportedBalance =
        reading.availableBalanceCents ?? item.availableBalance;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: isCredit
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: isCredit ? const Color(0xFF2E9E5B) : theme.colorScheme.primary,
                size: 44,
              ),
              const SizedBox(width: Tokens.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.merchant.isNotEmpty ? item.merchant : type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (item.bankName.isNotEmpty)
                          item.bankName
                        else if (item.appLabel.isNotEmpty)
                          item.appLabel,
                        if (reading.accountLast4.isNotEmpty)
                          '••${reading.accountLast4}'
                        else if (reading.counterpartyLast4.isNotEmpty)
                          '→ ••${reading.counterpartyLast4}'
                        else if (item.accountLast4.isNotEmpty)
                          '••${item.accountLast4}',
                        DateFormat('d MMM, HH:mm').format(item.receivedAt),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                formatMoney(type.sign() * (item.amount ?? 0), settings.currencySymbol,
                    signed: true),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isCredit ? const Color(0xFF2E9E5B) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s12),
          // The original text, so the user can always check what we read.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Tokens.s12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Tokens.rControl),
            ),
            child: Text(
              item.body.isEmpty ? item.title : item.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (reportedBalance != null) ...[
            const SizedBox(height: Tokens.s8),
            Row(
              children: [
                Icon(Icons.account_balance_rounded,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bank reports balance ${formatMoney(reportedBalance, settings.currencySymbol)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          if (notYours) ...[
            const SizedBox(height: Tokens.s8),
            Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 14, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reading.counterpartyLast4.isEmpty
                        ? 'This names an account that isn’t yours — check before saving.'
                        : 'Account ••${reading.counterpartyLast4} isn’t one of yours. '
                            'Save this only if the money moved on an account you hold.',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
          if (item.alsoSeenFrom.isNotEmpty) ...[
            const SizedBox(height: Tokens.s8),
            Row(
              children: [
                Icon(Icons.merge_rounded, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Also reported by ${item.alsoSeenFrom} — merged into one',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ],
          if (lowConfidence) ...[
            const SizedBox(height: Tokens.s8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Partly guessed — check the details before saving.',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Tokens.s12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(notificationCaptureProvider).ignoreItem(item.id),
                  child: const Text('Ignore'),
                ),
              ),
              const SizedBox(width: Tokens.s8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(matched == null ? 'Review & save' : 'Save to ${matched.name}'),
                  onPressed: accounts.isEmpty
                      ? null
                      : () => showAppSheet(
                            context,
                            InboxConfirmSheet(item: item),
                          ),
                ),
              ),
            ],
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s8),
              child: Text('Add an account first to save this.',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

class _ReviewedRow extends ConsumerWidget {
  final InboxItem item;
  final List<Account> accounts;

  const _ReviewedRow({required this.item, required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final confirmed = item.status == InboxStatus.confirmed.index;
    final type = item.txType != null ? TxType.values[item.txType!] : TxType.expense;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s8),
      leading: Icon(
        confirmed ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
        color: confirmed
            ? const Color(0xFF2E9E5B)
            : theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(item.merchant.isNotEmpty ? item.merchant : type.label,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${confirmed ? 'Saved' : 'Ignored'} · ${DateFormat('d MMM').format(item.receivedAt)}',
        style: theme.textTheme.labelSmall,
      ),
      trailing: Text(
        formatMoney(item.amount ?? 0, settings.currencySymbol),
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Confirmation sheet: pick the account and category, adjust anything the
/// parser got wrong, then save.
class InboxConfirmSheet extends ConsumerStatefulWidget {
  final InboxItem item;
  const InboxConfirmSheet({super.key, required this.item});

  @override
  ConsumerState<InboxConfirmSheet> createState() => _InboxConfirmSheetState();
}

class _InboxConfirmSheetState extends ConsumerState<InboxConfirmSheet> {
  late final amount =
      TextEditingController(text: centsToEditText(widget.item.amount ?? 0));
  late final description = TextEditingController(text: widget.item.merchant);
  late TxType type;
  late ParsedNotification reading;
  String? accountId;
  String? categoryId;
  bool rememberMatch = true;
  bool syncBalance = true;
  Transaction? ledgerDuplicate;

  @override
  void initState() {
    super.initState();
    final accounts = ref.read(accountsProvider).valueOrNull ?? const <Account>[];
    reading = resolveOwnership(
      Dedupe.reparse(widget.item),
      NotificationCaptureService.ownAccountDigits(accounts),
    );
    type = reading.type ??
        (widget.item.txType != null
            ? TxType.values[widget.item.txType!]
            : TxType.expense);
    accountId = widget.item.matchedAccountId;
    categoryId = widget.item.suggestedCategoryId;
    syncBalance = ref.read(settingsProvider).syncBalanceFromBank;
    // Digits introduced by "paid to" or "from" belong to whoever was on the
    // other side until the user says otherwise, so don't offer to learn them.
    final allDirectional = reading.accountRefs.isNotEmpty &&
        reading.accountRefs.every((r) => r.role != AccountRole.unspecified);
    rememberMatch = reading.ownership == Ownership.mine ||
        (reading.ownership == Ownership.unknown && !allDirectional);
    _checkLedger();
  }

  /// What the "always match" checkbox would teach. Never the other party's
  /// account number — learning that is what lands the next payment on the
  /// wrong account.
  String get _matchHint {
    if (reading.accountLast4.isNotEmpty) return reading.accountLast4;
    if (reading.ownership == Ownership.someoneElse) {
      return widget.item.bankName.toLowerCase();
    }
    return widget.item.accountLast4.isNotEmpty
        ? widget.item.accountLast4
        : widget.item.bankName.toLowerCase();
  }

  /// The balance the message quotes, re-read rather than taken from storage so
  /// items captured before a parser fix show the corrected figure.
  int? get _reportedBalance =>
      reading.availableBalanceCents ?? widget.item.availableBalance;

  /// Warns if this purchase already exists in the ledger — e.g. it was typed
  /// in manually, or auto-saved earlier.
  Future<void> _checkLedger() async {
    final match = await ref
        .read(notificationCaptureProvider)
        .findLedgerDuplicate(widget.item, accountId: accountId);
    if (mounted) setState(() => ledgerDuplicate = match);
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
    final hint = _matchHint;
    final reportedBalance = _reportedBalance;

    return SheetScaffold(
      title: 'Save transaction',
      actionLabel: ledgerDuplicate != null ? 'Save anyway' : 'Save',
      onAction: _save,
      children: [
        if (ledgerDuplicate != null) ...[
          Container(
            padding: const EdgeInsets.all(Tokens.s12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(Tokens.rControl),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: theme.colorScheme.error),
                const SizedBox(width: Tokens.s8),
                Expanded(
                  child: Text(
                    'You already have a ${formatMoney(ledgerDuplicate!.amount, ref.watch(settingsProvider).currencySymbol)} '
                    'transaction on ${formatDay(parseDayKey(ledgerDuplicate!.day))}. '
                    'This might be the same one.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s8),
          OutlinedButton.icon(
            icon: const Icon(Icons.block_rounded, size: 18),
            label: const Text('Not a new transaction — discard'),
            onPressed: () async {
              await ref.read(notificationCaptureProvider).ignoreItem(widget.item.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: Tokens.s16),
        ],
        Container(
          padding: const EdgeInsets.all(Tokens.s12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Tokens.rControl),
          ),
          child: Text(
            widget.item.body.isEmpty ? widget.item.title : widget.item.body,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: Tokens.s16),
        SegmentedButton<TxType>(
          showSelectedIcon: false,
          segments: [
            for (final t in [TxType.expense, TxType.income, TxType.refund])
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: Tokens.s12),
        TextField(
          controller: description,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: Tokens.s12),
        DropdownMenu<String>(
          expandedInsets: EdgeInsets.zero,
          label: const Text('Account'),
          initialSelection: accountId,
          dropdownMenuEntries: [
            for (final a in accounts) DropdownMenuEntry(value: a.id, label: a.name),
          ],
          onSelected: (v) {
            setState(() => accountId = v);
            _checkLedger();
          },
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: Tokens.s4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: rememberMatch,
            onChanged: (v) => setState(() => rememberMatch = v ?? false),
            title: Text('Always match “$hint” to this account',
                style: theme.textTheme.bodySmall),
          ),
        ],
        if (reportedBalance != null && _selectedAccountSyncable(accounts))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: syncBalance,
            onChanged: (v) => setState(() => syncBalance = v ?? false),
            title: Text(
              'Set balance to ${formatMoney(reportedBalance, ref.watch(settingsProvider).currencySymbol)} '
              '(what the bank reported)',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: Tokens.s8),
          Row(
            children: [
              Text('Category', style: theme.textTheme.titleSmall),
              if (widget.item.suggestedCategoryId != null &&
                  categoryId == widget.item.suggestedCategoryId) ...[
                const SizedBox(width: Tokens.s8),
                Icon(Icons.auto_awesome_rounded,
                    size: 13, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('remembered',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ],
          ),
          const SizedBox(height: Tokens.s8),
          Wrap(
            spacing: Tokens.s8,
            runSpacing: Tokens.s8,
            children: [
              for (final c in categories)
                ChoiceChip(
                  avatar: Icon(appIcon(c.iconCode), size: 16, color: Color(c.colorValue)),
                  label: Text(c.name),
                  selected: categoryId == c.id,
                  onSelected: (_) => setState(() => categoryId = c.id),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// "Available balance" only means the account's balance on everyday
  /// accounts — on a credit card it's available credit.
  bool _selectedAccountSyncable(List<Account> accounts) {
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    return account != null && balanceSyncSuitable(account);
  }

  Future<void> _save() async {
    final cents = parseMoneyToCents(amount.text);
    if (cents == null || cents <= 0 || accountId == null) return;

    // Remember the hint so future notifications from this card land here.
    final hint = _matchHint;
    if (rememberMatch && hint.isNotEmpty) {
      await _addHintToAccount(accountId!, hint);
    }

    await ref.read(notificationCaptureProvider).confirmItem(
          widget.item,
          accountId: accountId!,
          categoryId: categoryId,
          amountOverride: cents,
          typeOverride: type,
          descriptionOverride: description.text.trim(),
          syncBalance: syncBalance,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addHintToAccount(String id, String hint) async {
    final db = ref.read(dbProvider);
    final account =
        await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
    if (account == null) return;
    final hints = account.notificationHints
        .split(',')
        .map((h) => h.trim().toLowerCase())
        .where((h) => h.isNotEmpty)
        .toSet()
      ..add(hint.toLowerCase());
    await (db.update(db.accounts)..where((a) => a.id.equals(id)))
        .write(AccountsCompanion(notificationHints: Value(hints.join(','))));
  }
}
