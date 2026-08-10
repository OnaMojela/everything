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

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final balances = ref.watch(balancesProvider);
    final theme = Theme.of(context);

    if (accounts.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Add your first account',
        subtitle:
            'Checking, savings, cash, credit cards, investments, loans, crypto — track them all in one place.',
        actionLabel: 'New account',
        onAction: () => showAppSheet(context, const AccountEditorSheet()),
      );
    }

    final netWorth = accounts
        .where((a) => a.includeInNetWorth)
        .fold<int>(0, (s, a) => s + (balances[a.id] ?? 0));
    final assets = accounts
        .where((a) => a.includeInNetWorth && (balances[a.id] ?? 0) >= 0)
        .fold<int>(0, (s, a) => s + (balances[a.id] ?? 0));
    final debts = netWorth - assets;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net worth',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(formatMoney(netWorth, settings.currencySymbol),
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: Tokens.s8),
              Row(
                children: [
                  Text('Assets ${formatMoney(assets, settings.currencySymbol)}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: const Color(0xFF2E9E5B))),
                  const SizedBox(width: Tokens.s16),
                  if (debts < 0)
                    Text('Debt ${formatMoney(debts, settings.currencySymbol)}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.error)),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader('Accounts'),
        for (final a in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s8),
            child: AppCard(
              onTap: () => showAppSheet(context, AccountEditorSheet(existing: a)),
              child: Row(
                children: [
                  IconBadge(
                      icon: AccountType.values[a.accountType].icon,
                      color: Color(a.colorValue),
                      size: 46),
                  const SizedBox(width: Tokens.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(AccountType.values[a.accountType].label,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(balances[a.id] ?? 0, settings.currencySymbol),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: (balances[a.id] ?? 0) < 0 ? theme.colorScheme.error : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class AccountEditorSheet extends ConsumerStatefulWidget {
  final Account? existing;
  const AccountEditorSheet({super.key, this.existing});

  @override
  ConsumerState<AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends ConsumerState<AccountEditorSheet> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final initial = TextEditingController(
      text: widget.existing == null ? '' : centsToEditText(widget.existing!.initialBalance));
  late AccountType type = widget.existing != null
      ? AccountType.values[widget.existing!.accountType]
      : AccountType.checking;
  late final hints =
      TextEditingController(text: widget.existing?.notificationHints ?? '');
  late Color color =
      widget.existing != null ? Color(widget.existing!.colorValue) : itemColors[1];
  late bool inNetWorth = widget.existing?.includeInNetWorth ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetScaffold(
      title: widget.existing == null ? 'New account' : 'Edit account',
      actionLabel: widget.existing == null ? 'Create account' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context, 'account and all its transactions')) {
                  await ref.read(repoProvider).deleteAccount(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        TextField(
          controller: name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: Tokens.s16),
        Text('Type', style: theme.textTheme.titleSmall),
        const SizedBox(height: Tokens.s8),
        Wrap(
          spacing: Tokens.s8,
          runSpacing: Tokens.s8,
          children: [
            for (final t in AccountType.values)
              ChoiceChip(
                avatar: Icon(t.icon, size: 16),
                label: Text(t.label),
                selected: type == t,
                onSelected: (_) => setState(() => type = t),
              ),
          ],
        ),
        const SizedBox(height: Tokens.s16),
        TextField(
          controller: initial,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
              labelText: 'Starting balance', helperText: 'Use a negative value for debt'),
        ),
        const SizedBox(height: Tokens.s16),
        TextField(
          controller: hints,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: 'Bank notification matching',
            hintText: 'e.g. 8754, nedbank',
            helperMaxLines: 3,
            helperText:
                'The last 4 digits of this account and your bank’s name. Notifications '
                'are only counted against this account when they name these digits.',
          ),
        ),
        const SizedBox(height: Tokens.s16),
        ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
        const SizedBox(height: Tokens.s8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include in net worth'),
          value: inNetWorth,
          onChanged: (v) => setState(() => inNetWorth = v),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) return;
    final db = ref.read(dbProvider);
    final companion = AccountsCompanion(
      name: Value(name.text.trim()),
      accountType: Value(type.index),
      colorValue: Value(color.toARGB32()),
      initialBalance: Value(parseMoneyToCents(initial.text) ?? 0),
      includeInNetWorth: Value(inNetWorth),
      notificationHints: Value(_cleanHints(hints.text)),
    );
    if (widget.existing == null) {
      await db.into(db.accounts).insert(companion.copyWith(
          id: Value(newId()),
          sortOrder: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000)));
    } else {
      await (db.update(db.accounts)..where((a) => a.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Stored lowercase and comma-separated, which is how matching reads them.
  String _cleanHints(String raw) => raw
      .split(',')
      .map((h) => h.trim().toLowerCase())
      .where((h) => h.isNotEmpty)
      .toSet()
      .join(',');
}
