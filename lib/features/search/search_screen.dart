import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../finance/accounts_tab.dart';
import '../finance/bills_goals_tabs.dart';
import '../finance/transactions_tab.dart';
import '../productivity/tasks_tab.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String query = '';

  bool _match(String q, List<String?> fields) =>
      fields.any((f) => f != null && f.toLowerCase().contains(q));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final q = query.trim().toLowerCase();

    final habits = ref.watch(habitsProvider).valueOrNull ?? const [];
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const [];
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final bills = ref.watch(billsProvider).valueOrNull ?? const [];
    final goals = ref.watch(goalsProvider).valueOrNull ?? const [];
    final cats = {
      for (final c in ref.watch(categoriesProvider).valueOrNull ?? const []) c.id: c
    };

    final hHits = q.isEmpty
        ? []
        : habits
            .where((h) => _match(q, [h.title, h.description, h.note]))
            .take(6)
            .toList();
    final tHits = q.isEmpty
        ? []
        : tasks
            .where((t) => _match(q, [t.title, t.note, t.category, t.tags]))
            .take(6)
            .toList();
    final txHits = q.isEmpty
        ? []
        : txs
            .where((t) => _match(q, [t.description, t.merchant, t.note, t.tags]))
            .take(8)
            .toList();
    final aHits =
        q.isEmpty ? [] : accounts.where((a) => _match(q, [a.name])).take(4).toList();
    final bHits =
        q.isEmpty ? [] : bills.where((b) => _match(q, [b.name])).take(4).toList();
    final gHits = q.isEmpty
        ? []
        : goals.where((g) => _match(q, [g.name, g.note])).take(4).toList();

    final noResults = q.isNotEmpty &&
        hHits.isEmpty &&
        tHits.isEmpty &&
        txHits.isEmpty &&
        aHits.isEmpty &&
        bHits.isEmpty &&
        gHits.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            hintText: 'Search everything…',
            border: InputBorder.none,
            filled: false,
          ),
        ),
      ),
      body: q.isEmpty
          ? EmptyState(
              icon: Icons.search_rounded,
              title: 'Search everything',
              subtitle:
                  'Habits, tasks, transactions, accounts, bills and goals — all from one place.',
            )
          : noResults
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No results for “$query”',
                )
              : ListView(
                  padding:
                      const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s24),
                  children: [
                    if (hHits.isNotEmpty) ...[
                      const SectionHeader('Habits'),
                      AppCard(
                        padding: const EdgeInsets.all(Tokens.s8),
                        child: Column(
                          children: [
                            for (final h in hHits)
                              ListTile(
                                leading: IconBadge(
                                    icon: appIcon(h.iconCode),
                                    color: Color(h.colorValue),
                                    size: 38),
                                title: Text(h.title),
                                onTap: () => context.push('/habit/${h.id}'),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (tHits.isNotEmpty) ...[
                      const SectionHeader('Tasks'),
                      AppCard(
                        padding: const EdgeInsets.all(Tokens.s8),
                        child: Column(
                          children: [
                            for (final t in tHits)
                              ListTile(
                                leading: Icon(
                                  t.completed
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: t.completed
                                      ? const Color(0xFF2E9E5B)
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: Text(t.title),
                                subtitle: t.dueDay == null
                                    ? null
                                    : Text(formatDay(parseDayKey(t.dueDay!))),
                                onTap: () => showAppSheet(
                                    context, TaskEditorSheet(existing: t)),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (txHits.isNotEmpty) ...[
                      const SectionHeader('Transactions'),
                      AppCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Tokens.s12, vertical: Tokens.s4),
                        child: Column(
                          children: [
                            for (final t in txHits)
                              TransactionRow(
                                tx: t,
                                category: cats[t.categoryId],
                                accounts: accounts,
                                symbol: settings.currencySymbol,
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (aHits.isNotEmpty) ...[
                      const SectionHeader('Accounts'),
                      AppCard(
                        padding: const EdgeInsets.all(Tokens.s8),
                        child: Column(
                          children: [
                            for (final a in aHits)
                              ListTile(
                                leading: IconBadge(
                                    icon: AccountType.values[a.accountType].icon,
                                    color: Color(a.colorValue),
                                    size: 38),
                                title: Text(a.name),
                                onTap: () => showAppSheet(
                                    context, AccountEditorSheet(existing: a)),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (bHits.isNotEmpty) ...[
                      const SectionHeader('Bills'),
                      AppCard(
                        padding: const EdgeInsets.all(Tokens.s8),
                        child: Column(
                          children: [
                            for (final b in bHits)
                              ListTile(
                                leading: const Icon(Icons.event_repeat_rounded),
                                title: Text(b.name),
                                subtitle:
                                    Text('Due ${formatDay(parseDayKey(b.nextDue))}'),
                                trailing: Text(
                                    formatMoney(b.amount, settings.currencySymbol)),
                                onTap: () => showAppSheet(
                                    context, BillEditorSheet(existing: b)),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (gHits.isNotEmpty) ...[
                      const SectionHeader('Goals'),
                      AppCard(
                        padding: const EdgeInsets.all(Tokens.s8),
                        child: Column(
                          children: [
                            for (final g in gHits)
                              ListTile(
                                leading: IconBadge(
                                    icon: appIcon(g.iconCode),
                                    color: Color(g.colorValue),
                                    size: 38),
                                title: Text(g.name),
                                onTap: () => showAppSheet(
                                    context, GoalEditorSheet(existing: g)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
