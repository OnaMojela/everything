import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Every dashboard section is a widget the user can enable, hide and reorder.
abstract final class DashWidgetIds {
  static const todayHabits = 'todayHabits';
  static const todayTasks = 'todayTasks';
  static const todayPlanner = 'todayPlanner';
  static const focus = 'focus';
  static const streaks = 'streaks';
  static const balances = 'balances';
  static const recentTransactions = 'recentTransactions';
  static const budgets = 'budgets';
  static const billsDue = 'billsDue';
  static const goals = 'goals';

  static const productivity = [todayHabits, todayTasks, todayPlanner, focus, streaks];
  static const finance = [balances, recentTransactions, budgets, billsDue, goals];
  static const all = [...productivity, ...finance];

  static String label(String id) => switch (id) {
        todayHabits => "Today's habits",
        todayTasks => "Today's tasks",
        todayPlanner => "Today's plan",
        focus => 'Focus',
        streaks => 'Streaks',
        balances => 'Accounts',
        recentTransactions => 'Recent transactions',
        budgets => 'Budgets',
        billsDue => 'Bills due',
        goals => 'Savings goals',
        _ => id,
      };
}

class AppSettings {
  final AppThemeMode themeMode;
  final int accentIndex;
  final bool showProductivity;
  final bool showFinance;
  final bool compactMode;
  final bool weekStartsMonday;
  final String currencySymbol;
  final List<String> dashboardWidgets;
  final String userName;
  final bool appLockEnabled;

  /// Read bank notifications and suggest transactions (Android only).
  final bool captureEnabled;

  /// File confidently-parsed, account-matched captures without asking.
  final bool captureAutoConfirm;

  /// Packages the user never wants captured.
  final List<String> captureMutedPackages;

  /// Trust the balance a bank message reports and correct the account to match.
  final bool syncBalanceFromBank;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accentIndex = 0,
    this.showProductivity = true,
    this.showFinance = true,
    this.compactMode = false,
    this.weekStartsMonday = true,
    this.currencySymbol = 'R',
    this.dashboardWidgets = DashWidgetIds.all,
    this.userName = '',
    this.appLockEnabled = false,
    this.captureEnabled = false,
    this.captureAutoConfirm = false,
    this.captureMutedPackages = const [],
    this.syncBalanceFromBank = true,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? accentIndex,
    bool? showProductivity,
    bool? showFinance,
    bool? compactMode,
    bool? weekStartsMonday,
    String? currencySymbol,
    List<String>? dashboardWidgets,
    String? userName,
    bool? appLockEnabled,
    bool? captureEnabled,
    bool? captureAutoConfirm,
    List<String>? captureMutedPackages,
    bool? syncBalanceFromBank,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accentIndex: accentIndex ?? this.accentIndex,
        showProductivity: showProductivity ?? this.showProductivity,
        showFinance: showFinance ?? this.showFinance,
        compactMode: compactMode ?? this.compactMode,
        weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
        currencySymbol: currencySymbol ?? this.currencySymbol,
        dashboardWidgets: dashboardWidgets ?? this.dashboardWidgets,
        userName: userName ?? this.userName,
        appLockEnabled: appLockEnabled ?? this.appLockEnabled,
        captureEnabled: captureEnabled ?? this.captureEnabled,
        captureAutoConfirm: captureAutoConfirm ?? this.captureAutoConfirm,
        captureMutedPackages: captureMutedPackages ?? this.captureMutedPackages,
        syncBalanceFromBank: syncBalanceFromBank ?? this.syncBalanceFromBank,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.index,
        'accentIndex': accentIndex,
        'showProductivity': showProductivity,
        'showFinance': showFinance,
        'compactMode': compactMode,
        'weekStartsMonday': weekStartsMonday,
        'currencySymbol': currencySymbol,
        'dashboardWidgets': dashboardWidgets,
        'userName': userName,
        'appLockEnabled': appLockEnabled,
        'captureEnabled': captureEnabled,
        'captureAutoConfirm': captureAutoConfirm,
        'captureMutedPackages': captureMutedPackages,
        'syncBalanceFromBank': syncBalanceFromBank,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        themeMode: AppThemeMode.values[(json['themeMode'] as int?) ?? 0],
        accentIndex: (json['accentIndex'] as int?) ?? 0,
        showProductivity: (json['showProductivity'] as bool?) ?? true,
        showFinance: (json['showFinance'] as bool?) ?? true,
        compactMode: (json['compactMode'] as bool?) ?? false,
        weekStartsMonday: (json['weekStartsMonday'] as bool?) ?? true,
        currencySymbol: (json['currencySymbol'] as String?) ?? 'R',
        dashboardWidgets: ((json['dashboardWidgets'] as List?) ?? DashWidgetIds.all).cast<String>(),
        userName: (json['userName'] as String?) ?? '',
        appLockEnabled: (json['appLockEnabled'] as bool?) ?? false,
        captureEnabled: (json['captureEnabled'] as bool?) ?? false,
        captureAutoConfirm: (json['captureAutoConfirm'] as bool?) ?? false,
        captureMutedPackages:
            ((json['captureMutedPackages'] as List?) ?? const []).cast<String>(),
        syncBalanceFromBank: (json['syncBalanceFromBank'] as bool?) ?? true,
      );

  AccentColor get accent => accentPalette[accentIndex.clamp(0, accentPalette.length - 1)];
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app_settings_v1';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
  }

  Future<void> update(AppSettings Function(AppSettings) fn) async {
    state = fn(state);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
