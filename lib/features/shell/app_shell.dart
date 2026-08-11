import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';

/// Breakpoints: phones get a bottom bar, tablets/desktop get a side rail.
abstract final class Breakpoints {
  static const compact = 700.0; // below: bottom navigation
  static const expanded = 1100.0; // above: rail with labels + wider content
  static const contentMaxWidth = 1080.0;
}

class _Dest {
  final int branch;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Dest(this.branch, this.label, this.icon, this.selectedIcon);
}

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= Breakpoints.compact;
    final extendedRail = width >= Breakpoints.expanded;

    final dests = <_Dest>[
      const _Dest(0, 'Home', Icons.grid_view_outlined, Icons.grid_view_rounded),
      if (settings.showProductivity)
        const _Dest(
          1,
          'Productivity',
          Icons.check_circle_outline_rounded,
          Icons.check_circle_rounded,
        ),
      if (settings.showFinance)
        const _Dest(
          2,
          'Finance',
          Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet_rounded,
        ),
      const _Dest(
        3,
        'Analytics',
        Icons.insights_outlined,
        Icons.insights_rounded,
      ),
    ];

    var selected = dests.indexWhere((d) => d.branch == shell.currentIndex);
    if (selected < 0) selected = 0;

    void go(int i) {
      final d = dests[i];
      shell.goBranch(d.branch, initialLocation: d.branch == shell.currentIndex);
    }

    // Content is centred and width-capped so it stays readable on wide monitors.
    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Breakpoints.contentMaxWidth,
        ),
        child: shell,
      ),
    );

    if (!useRail) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: go,
          destinations: [
            for (final d in dests)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          // The rail bottom-aligns its trailing buttons by filling the height,
          // which overflows once the window is shorter than logo +
          // destinations + buttons — landscape on a phone, most obviously.
          // Letting it scroll below that height keeps everything reachable,
          // while the minimum height preserves the bottom alignment whenever
          // there is room.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: selected,
                    onDestinationSelected: go,
                    extended: extendedRail,
                    minExtendedWidth: 200,
                    backgroundColor: theme.colorScheme.surfaceContainerLow,
                    labelType: extendedRail
                        ? null
                        : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: EdgeInsets.fromLTRB(
                        extendedRail ? 4 : 0,
                        Tokens.s16,
                        0,
                        Tokens.s8,
                      ),
                      child: extendedRail
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _Logo(color: theme.colorScheme.primary),
                                const SizedBox(width: Tokens.s12),
                                Text(
                                  'Everything',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : _Logo(color: theme.colorScheme.primary),
                    ),
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: Tokens.s16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.search_rounded),
                                tooltip: 'Search',
                                onPressed: () => context.push('/search'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings_outlined),
                                tooltip: 'Settings',
                                onPressed: () => context.push('/settings'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    destinations: [
                      for (final d in dests)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final Color color;
  const _Logo({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.all_inclusive_rounded,
        size: 20,
        color: Colors.white,
      ),
    );
  }
}

/// Shared app bar actions. On wide layouts search/settings live in the rail,
/// so they're omitted here to avoid duplication.
List<Widget> shellActions(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= Breakpoints.compact) return const [];
  return [
    IconButton(
      icon: const Icon(Icons.search_rounded),
      tooltip: 'Search',
      onPressed: () => context.push('/search'),
    ),
    IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => context.push('/settings'),
    ),
    const SizedBox(width: 4),
  ];
}
