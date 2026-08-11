import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import 'core/platform/platform_support.dart';
import 'core/services/lock_gate.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/finance/categories_screen.dart';
import 'features/finance/finance_screen.dart';
import 'features/finance/inbox_screen.dart';
import 'features/finance/transactions_tab.dart';
import 'features/productivity/habit_detail_screen.dart';
import 'features/productivity/productivity_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/productivity', builder: (_, _) => const ProductivityScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/finance', builder: (_, _) => const FinanceScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/analytics', builder: (_, _) => const AnalyticsScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const _Centered(child: SearchScreen()),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const _Centered(child: SettingsScreen()),
      ),
      GoRoute(
        path: '/categories',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const _Centered(child: CategoriesScreen()),
      ),
      GoRoute(
        path: '/inbox',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const _Centered(child: InboxScreen()),
      ),
      GoRoute(
        path: '/quick-add',
        parentNavigatorKey: _rootKey,
        builder: (context, _) => _Centered(
          child: Scaffold(
            appBar: AppBar(title: const Text('Quick add')),
            body: const TransactionEditorSheet(),
          ),
        ),
      ),
      GoRoute(
        path: '/habit/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            _Centered(child: HabitDetailScreen(habitId: state.pathParameters['id']!)),
      ),
    ],
  );
});

/// Keeps pushed pages readable on wide monitors.
class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});

  @override
  Widget build(BuildContext context) {
    // Painted across the whole viewport, not just the capped content column.
    // A pushed route has no Scaffold of its own behind it, so on a wide window
    // the margins either side were left unpainted and showed through to the
    // route underneath — which is why Settings looked different from every
    // screen reached through the navigation rail.
    //
    // Reading the colour from the theme rather than naming one keeps it
    // correct across Light, Dark and OLED and every accent.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMaxWidth),
          child: child,
        ),
      ),
    );
  }
}

class EverythingApp extends ConsumerStatefulWidget {
  const EverythingApp({super.key});

  @override
  ConsumerState<EverythingApp> createState() => _EverythingAppState();
}

class _EverythingAppState extends ConsumerState<EverythingApp> {
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    // Home-screen widget deep links: quick-add buttons open the editor.
    if (supportsHomeWidgets) {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
      _widgetClicks = HomeWidget.widgetClicked.listen(_handleWidgetUri);
    }
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    super.dispose();
  }

  void _handleWidgetUri(Uri? uri) {
    if (uri == null) return;
    if (uri.host == 'add') {
      ref.read(routerProvider).push('/quick-add');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final accent = settings.accent.color;

    final light = buildAppTheme(
      brightness: Brightness.light,
      accent: accent,
      compact: settings.compactMode,
    );
    final dark = buildAppTheme(
      brightness: Brightness.dark,
      accent: accent,
      oled: settings.themeMode == AppThemeMode.oled,
      compact: settings.compactMode,
    );

    final mode = switch (settings.themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark || AppThemeMode.oled => ThemeMode.dark,
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            mode == ThemeMode.light ? Brightness.dark : Brightness.light,
      ),
      child: MaterialApp.router(
        title: 'Everything',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        routerConfig: router,
        builder: (context, child) => LockGate(child: child ?? const SizedBox()),
      ),
    );
  }
}
