import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../productivity/habit_widgets.dart';
import '../shell/app_shell.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ids = settings.dashboardWidgets.where((id) {
      if (DashWidgetIds.productivity.contains(id) && !settings.showProductivity) return false;
      if (DashWidgetIds.finance.contains(id) && !settings.showFinance) return false;
      return true;
    }).toList();

    final greeting = switch (DateTime.now().hour) {
      < 5 => 'Good night',
      < 12 => 'Good morning',
      < 18 => 'Good afternoon',
      _ => 'Good evening',
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.userName.isEmpty ? greeting : '$greeting, ${settings.userName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              DateFormat('EEEE, d MMMM').format(DateTime.now()),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        toolbarHeight: 68,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Customize dashboard',
            onPressed: () => _openCustomize(context, ref),
          ),
          ...shellActions(context),
        ],
      ),
      body: ids.isEmpty
          ? EmptyState(
              icon: Icons.dashboard_customize_rounded,
              title: 'Your dashboard is empty',
              subtitle: 'Add widgets to build a home screen that matches your priorities.',
              actionLabel: 'Customize',
              onAction: () => _openCustomize(context, ref),
            )
          : LayoutBuilder(builder: (context, constraints) {
              // Wide viewports get two balanced columns instead of one long list.
              final twoColumn = constraints.maxWidth >= 780;
              if (!twoColumn) {
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      Tokens.s16, Tokens.s4, Tokens.s16, Tokens.s24),
                  itemCount: ids.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Tokens.s12),
                  itemBuilder: (context, i) => _buildWidget(ids[i]),
                );
              }
              final left = <String>[];
              final right = <String>[];
              for (var i = 0; i < ids.length; i++) {
                (i.isEven ? left : right).add(ids[i]);
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s16, Tokens.s4, Tokens.s16, Tokens.s24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _column(left)),
                    const SizedBox(width: Tokens.s12),
                    Expanded(child: _column(right)),
                  ],
                ),
              );
            }),
    );
  }

  Widget _column(List<String> ids) => Column(
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s12),
              child: _buildWidget(id),
            ),
        ],
      );

  Widget _buildWidget(String id) => switch (id) {
        DashWidgetIds.todayHabits => const _TodayHabitsCard(),
        DashWidgetIds.todayTasks => const _TodayTasksCard(),
        DashWidgetIds.todayPlanner => const _TodayPlannerCard(),
        DashWidgetIds.focus => const _FocusCard(),
        DashWidgetIds.streaks => const _StreaksCard(),
        DashWidgetIds.balances => const _BalancesCard(),
        DashWidgetIds.recentTransactions => const _RecentTransactionsCard(),
        DashWidgetIds.budgets => const _BudgetsCard(),
        DashWidgetIds.billsDue => const _BillsDueCard(),
        DashWidgetIds.goals => const _GoalsCard(),
        _ => const SizedBox.shrink(),
      };

  void _openCustomize(BuildContext context, WidgetRef ref) {
    showAppSheet(context, const _CustomizeDashboardSheet());
  }
}

// ---------------------------------------------------------------------------
// Customize sheet: toggle + reorder every widget
// ---------------------------------------------------------------------------

class _CustomizeDashboardSheet extends ConsumerWidget {
  const _CustomizeDashboardSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final enabled = settings.dashboardWidgets;
    final disabled = DashWidgetIds.all.where((id) => !enabled.contains(id)).toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s20, 0, Tokens.s20, Tokens.s8),
            child: Text('Customize dashboard', style: Theme.of(context).textTheme.headlineSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s20),
            child: Text(
              'Drag to reorder. Toggle to show or hide.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Tokens.s8),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s12),
              onReorderItem: (oldIndex, newIndex) {
                final list = [...enabled];
                if (oldIndex >= list.length) return;
                final item = list.removeAt(oldIndex);
                list.insert(newIndex.clamp(0, list.length), item);
                ref.read(settingsProvider.notifier).update((s) => s.copyWith(dashboardWidgets: list));
              },
              children: [
                for (final id in enabled)
                  SwitchListTile(
                    key: ValueKey(id),
                    title: Text(DashWidgetIds.label(id)),
                    secondary: const Icon(Icons.drag_indicator_rounded),
                    value: true,
                    onChanged: (_) => ref.read(settingsProvider.notifier).update(
                        (s) => s.copyWith(dashboardWidgets: [...enabled]..remove(id))),
                  ),
              ],
            ),
          ),
          if (disabled.isNotEmpty) ...[
            const Divider(indent: Tokens.s20, endIndent: Tokens.s20),
            for (final id in disabled)
              SwitchListTile(
                title: Text(DashWidgetIds.label(id)),
                secondary: const Icon(Icons.visibility_off_outlined),
                value: false,
                onChanged: (_) => ref.read(settingsProvider.notifier).update(
                    (s) => s.copyWith(dashboardWidgets: [...enabled, id])),
              ),
          ],
          const SizedBox(height: Tokens.s16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared dashboard card chrome
// ---------------------------------------------------------------------------

class _DashCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onOpen;
  final Widget child;

  const _DashCard({required this.title, required this.icon, this.onOpen, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Tokens.s8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (onOpen != null)
                Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: Tokens.s12),
          child,
        ],
      ),
    );
  }
}

class _MiniEmpty extends StatelessWidget {
  final String text;
  const _MiniEmpty(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Productivity widgets
// ---------------------------------------------------------------------------

class _TodayHabitsCard extends ConsumerWidget {
  const _TodayHabitsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const [];
    final entries = ref.watch(entriesForDayProvider(dayKey(today))).valueOrNull ?? const {};
    final due = habits.where((h) => habitDueOn(h, today)).toList();
    final done = due.where((h) => entries[h.id]?.completed ?? false).length;

    return _DashCard(
      title: due.isEmpty ? "Today's habits" : "Today's habits · $done/${due.length}",
      icon: Icons.repeat_rounded,
      onOpen: () => context.go('/productivity'),
      child: due.isEmpty
          ? const _MiniEmpty('No habits scheduled today.')
          : Column(
              children: [
                for (final h in due.take(5)) HabitRow(habit: h, entry: entries[h.id], dense: true),
                if (due.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.s4),
                    child: Text('+${due.length - 5} more',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
    );
  }
}

class _TodayTasksCard extends ConsumerWidget {
  const _TodayTasksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = (ref.watch(tasksProvider).valueOrNull ?? const [])
        .where((t) => !t.completed && (t.dueDay == null || t.dueDay == dayKey(today)))
        .toList();

    return _DashCard(
      title: "Today's tasks",
      icon: Icons.task_alt_rounded,
      onOpen: () => context.go('/productivity'),
      child: tasks.isEmpty
          ? const _MiniEmpty('All clear — nothing due today.')
          : Column(
              children: [
                for (final t in tasks.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Checkbox(
                            value: t.completed,
                            shape: const CircleBorder(),
                            onChanged: (v) =>
                                ref.read(repoProvider).setTaskCompleted(t, v ?? false),
                          ),
                        ),
                        const SizedBox(width: Tokens.s8),
                        Expanded(
                            child:
                                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (t.priority > 0)
                          Icon(Icons.flag_rounded,
                              size: 16, color: TaskPriority.values[t.priority].color),
                        if (t.dueTime != null) ...[
                          const SizedBox(width: 6),
                          Text(t.dueTime!,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TodayPlannerCard extends ConsumerWidget {
  const _TodayPlannerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(plannerEventsProvider(dayKey(today))).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return _DashCard(
      title: "Today's plan",
      icon: Icons.view_agenda_outlined,
      onOpen: () => context.go('/productivity'),
      child: events.isEmpty
          ? const _MiniEmpty('Nothing planned yet. Design your day in the planner.')
          : Column(
              children: [
                for (final e in events.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 30,
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              Text(
                                '${formatTimeOfDayMinutes(e.startMinutes)} – ${formatTimeOfDayMinutes(e.endMinutes)}',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FocusCard extends ConsumerWidget {
  const _FocusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(focusSessionsProvider).valueOrNull ?? const [];
    final todaySeconds = sessions
        .where((s) => dayKey(s.startedAt) == dayKey(today))
        .fold<int>(0, (a, s) => a + s.durationSeconds);
    final weekStart = startOfWeek(today);
    final weekSeconds = sessions
        .where((s) => !dateOnly(s.startedAt).isBefore(weekStart))
        .fold<int>(0, (a, s) => a + s.durationSeconds);

    return _DashCard(
      title: 'Focus',
      icon: Icons.center_focus_strong_rounded,
      onOpen: () => context.go('/productivity'),
      child: Row(
        children: [
          Expanded(
            child: _kv(context, 'Today', formatDuration(Duration(seconds: todaySeconds))),
          ),
          Expanded(
            child: _kv(context, 'This week', formatDuration(Duration(seconds: weekSeconds))),
          ),
          FilledButton.tonalIcon(
            onPressed: () => context.go('/productivity'),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k,
            style:
                theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(v, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _StreaksCard extends ConsumerWidget {
  const _StreaksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const [];
    final all = ref.watch(allEntriesProvider).valueOrNull ?? const [];
    final byHabit = <String, Map<String, HabitEntry>>{};
    for (final e in all) {
      (byHabit[e.habitId] ??= {})[e.day] = e;
    }
    final streaks = [
      for (final h in habits) (h, currentStreak(h, byHabit[h.id] ?? const {}))
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final top = streaks.where((s) => s.$2 > 0).take(4).toList();

    return _DashCard(
      title: 'Streaks',
      icon: Icons.local_fire_department_rounded,
      onOpen: () => context.go('/productivity'),
      child: top.isEmpty
          ? const _MiniEmpty('Complete habits to start building streaks.')
          : Row(
              children: [
                for (final (h, streak) in top)
                  Expanded(
                    child: Column(
                      children: [
                        IconBadge(
                            icon: appIcon(h.iconCode),
                            color: Color(h.colorValue)),
                        const SizedBox(height: 6),
                        Text('$streak🔥',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(h.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Finance widgets
// ---------------------------------------------------------------------------

class _BalancesCard extends ConsumerWidget {
  const _BalancesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final balances = ref.watch(balancesProvider);
    final netWorth = accounts
        .where((a) => a.includeInNetWorth)
        .fold<int>(0, (sum, a) => sum + (balances[a.id] ?? 0));
    final theme = Theme.of(context);

    return _DashCard(
      title: 'Accounts',
      icon: Icons.account_balance_wallet_rounded,
      onOpen: () => context.go('/finance'),
      child: accounts.isEmpty
          ? const _MiniEmpty('Add your first account to start tracking money.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net worth',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(formatMoney(netWorth, settings.currencySymbol),
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: Tokens.s12),
                for (final a in accounts.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(AccountType.values[a.accountType].icon,
                            size: 18, color: Color(a.colorValue)),
                        const SizedBox(width: Tokens.s8),
                        Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(formatMoney(balances[a.id] ?? 0, settings.currencySymbol),
                            style:
                                theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RecentTransactionsCard extends ConsumerWidget {
  const _RecentTransactionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
    final cats = {
      for (final c in ref.watch(categoriesProvider).valueOrNull ?? const <Category>[]) c.id: c
    };
    final theme = Theme.of(context);

    return _DashCard(
      title: 'Recent transactions',
      icon: Icons.receipt_long_rounded,
      onOpen: () => context.go('/finance'),
      child: txs.isEmpty
          ? const _MiniEmpty('No transactions yet.')
          : Column(
              children: [
                for (final t in txs.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        IconBadge(
                          icon: t.categoryId != null && cats[t.categoryId] != null
                              ? appIcon(cats[t.categoryId]!.iconCode)
                              : Icons.swap_horiz_rounded,
                          color: t.categoryId != null && cats[t.categoryId] != null
                              ? Color(cats[t.categoryId]!.colorValue)
                              : theme.colorScheme.primary,
                          size: 34,
                        ),
                        const SizedBox(width: Tokens.s12),
                        Expanded(
                          child: Text(
                            t.description.isNotEmpty
                                ? t.description
                                : (t.merchant.isNotEmpty
                                    ? t.merchant
                                    : cats[t.categoryId]?.name ?? TxType.values[t.txType].label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatMoney(TxType.values[t.txType].sign() * t.amount,
                              settings.currencySymbol,
                              signed: true),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: TxType.values[t.txType].sign() > 0
                                ? const Color(0xFF2E9E5B)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BudgetsCard extends ConsumerWidget {
  const _BudgetsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const [];
    final txs = ref.watch(transactionsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return _DashCard(
      title: 'Budgets',
      icon: Icons.donut_small_rounded,
      onOpen: () => context.go('/finance'),
      child: budgets.isEmpty
          ? const _MiniEmpty('Create a budget to keep spending intentional.')
          : Column(
              children: [
                for (final b in budgets.take(3))
                  Builder(builder: (context) {
                    final spent =
                        budgetSpent(b, txs, mondayStart: settings.weekStartsMonday);
                    final progress = b.amount <= 0 ? 0.0 : spent / b.amount;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(b.name, style: theme.textTheme.bodyMedium)),
                              Text(
                                '${formatMoney(spent, settings.currencySymbol)} / ${formatMoney(b.amount, settings.currencySymbol)}',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ProgressBar(progress: progress, color: theme.colorScheme.primary),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _BillsDueCard extends ConsumerWidget {
  const _BillsDueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final bills = ref.watch(billsProvider).valueOrNull ?? const [];
    final soon = bills
        .where((b) =>
            parseDayKey(b.nextDue).difference(today).inDays <= 14)
        .toList();
    final theme = Theme.of(context);

    return _DashCard(
      title: 'Bills due',
      icon: Icons.event_repeat_rounded,
      onOpen: () => context.go('/finance'),
      child: soon.isEmpty
          ? const _MiniEmpty('No bills due in the next two weeks.')
          : Column(
              children: [
                for (final b in soon.take(4))
                  Builder(builder: (context) {
                    final due = parseDayKey(b.nextDue);
                    final overdue = due.isBefore(today);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text(formatDay(due),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: overdue
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(width: Tokens.s12),
                          Text(formatMoney(b.amount, settings.currencySymbol),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _GoalsCard extends ConsumerWidget {
  const _GoalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final goals = ref.watch(goalsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return _DashCard(
      title: 'Savings goals',
      icon: Icons.flag_circle_rounded,
      onOpen: () => context.go('/finance'),
      child: goals.isEmpty
          ? const _MiniEmpty('Set a goal — an emergency fund is a great start.')
          : Row(
              children: [
                for (final g in goals.take(3))
                  Expanded(
                    child: Column(
                      children: [
                        ProgressRing(
                          progress: g.targetAmount <= 0 ? 0 : g.savedAmount / g.targetAmount,
                          color: Color(g.colorValue),
                          size: 54,
                          center: Icon(appIcon(g.iconCode),
                              size: 20, color: Color(g.colorValue)),
                        ),
                        const SizedBox(height: 6),
                        Text(g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium),
                        Text(
                          formatMoney(g.savedAmount, settings.currencySymbol),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
