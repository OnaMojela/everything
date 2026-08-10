import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../platform/platform_support.dart';
import '../utils/utils.dart';

/// Mirrors today's habits into the Android home-screen widget and handles
/// check-off taps coming back from it.
class WidgetSyncService {
  static const _dataKey = 'habits_data';
  static const habitsProviderName = 'HabitsWidgetProvider';
  static const quickAddProviderName = 'QuickAddWidgetProvider';

  static void attach(ProviderContainer container) {
    if (!supportsHomeWidgets) return;
    HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    container.listen(habitsProvider, (_, _) => _sync(container), fireImmediately: true);
    container.listen(entriesForDayProvider(dayKey(today)), (_, _) => _sync(container));
  }

  static Future<void> _sync(ProviderContainer container) async {
    final habits = container.read(habitsProvider).valueOrNull;
    final entries = container.read(entriesForDayProvider(dayKey(today))).valueOrNull;
    if (habits == null) return;
    await pushData(habits, entries ?? const {});
  }

  static Future<void> pushData(
      List<Habit> habits, Map<String, HabitEntry> entries) async {
    if (!supportsHomeWidgets) return;
    final due = habits.where((h) => habitDueOn(h, today)).take(6).toList();
    final data = [
      for (final h in due)
        {
          'id': h.id,
          'title': h.title,
          'done': entries[h.id]?.completed ?? false,
          'color': h.colorValue,
        },
    ];
    await HomeWidget.saveWidgetData(_dataKey, jsonEncode(data));
    await HomeWidget.updateWidget(androidName: habitsProviderName);
  }
}

/// Runs in a background isolate when a widget row is tapped — no UI, just a
/// quick database toggle and a widget refresh.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null || uri.host != 'togglehabit') return;
  final habitId = uri.queryParameters['id'];
  if (habitId == null) return;

  final db = AppDatabase();
  try {
    final habit = await (db.select(db.habits)..where((h) => h.id.equals(habitId)))
        .getSingleOrNull();
    if (habit == null) return;
    final day = dayKey(today);
    final entry = await (db.select(db.habitEntries)
          ..where((e) => e.habitId.equals(habitId) & e.day.equals(day)))
        .getSingleOrNull();

    final type = HabitType.values[habit.habitType];
    double newValue;
    switch (type) {
      case HabitType.check:
        newValue = (entry?.completed ?? false) ? 0 : 1;
      case HabitType.counter:
        newValue = (entry?.value ?? 0) + 1;
      case HabitType.numeric:
      case HabitType.duration:
      case HabitType.percent:
        // A widget tap on a measurable habit marks the goal reached.
        newValue = (entry?.completed ?? false) ? 0 : habit.targetValue;
    }
    await Repo(db).setHabitValue(habit, day, newValue);

    final habits = await (db.select(db.habits)..where((h) => h.archived.equals(false)))
        .get();
    final entries = await (db.select(db.habitEntries)..where((e) => e.day.equals(day)))
        .get();
    await WidgetSyncService.pushData(
        habits, {for (final e in entries) e.habitId: e});
  } finally {
    await db.close();
  }
}
