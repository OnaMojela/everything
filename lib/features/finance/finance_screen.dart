import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/notification_capture.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';
import '../shell/app_shell.dart';
import 'accounts_tab.dart';
import 'bills_goals_tabs.dart';
import 'budgets_tab.dart';
import 'transactions_tab.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAccounts =
        (ref.watch(accountsProvider).valueOrNull ?? const []).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          if (ref.watch(settingsProvider).captureEnabled) _inboxAction(context, ref),
          ...shellActions(context),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Accounts'),
            Tab(text: 'Transactions'),
            Tab(text: 'Budgets'),
            Tab(text: 'Bills'),
            Tab(text: 'Goals'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          AccountsTab(),
          TransactionsTab(),
          BudgetsTab(),
          BillsTab(),
          GoalsTab(),
        ],
      ),
      floatingActionButton: switch (_tabs.index) {
        0 => _fab('Account', () => showAppSheet(context, const AccountEditorSheet())),
        1 => hasAccounts
            ? _fab('Transaction',
                () => showAppSheet(context, const TransactionEditorSheet()))
            : null,
        2 => _fab('Budget', () => showAppSheet(context, const BudgetEditorSheet())),
        3 => _fab('Bill', () => showAppSheet(context, const BillEditorSheet())),
        4 => _fab('Goal', () => showAppSheet(context, const GoalEditorSheet())),
        _ => null,
      },
    );
  }

  /// Inbox button with a badge for transactions awaiting review.
  Widget _inboxAction(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingInboxCountProvider);
    return IconButton(
      tooltip: 'Transaction inbox',
      onPressed: () => context.push('/inbox'),
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text('$pending'),
        child: const Icon(Icons.inbox_rounded),
      ),
    );
  }

  Widget _fab(String label, VoidCallback onPressed) => FloatingActionButton.extended(
        heroTag: 'fab_fin',
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded),
        label: Text(label),
      );
}
