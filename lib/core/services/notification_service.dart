import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/db/database.dart';
import '../../data/logic/domain_logic.dart';
import '../platform/platform_support.dart';
import '../utils/utils.dart';

/// One service owns every notification concern: habit reminders, bill alerts,
/// the ongoing focus chip and pomodoro phase-end alarms.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _habitChannel = AndroidNotificationDetails(
    'habits', 'Habit reminders',
    channelDescription: 'Reminders for scheduled habits',
    importance: Importance.high, priority: Priority.high,
  );
  static const _billChannel = AndroidNotificationDetails(
    'bills', 'Bill reminders',
    channelDescription: 'Upcoming and due bills',
    importance: Importance.high, priority: Priority.high,
  );
  static const _focusChannel = AndroidNotificationDetails(
    'focus', 'Focus sessions',
    channelDescription: 'Running focus session and phase changes',
    importance: Importance.low, priority: Priority.low,
    ongoing: true, autoCancel: false, showWhen: true, usesChronometer: true,
  );
  static const _focusAlertChannel = AndroidNotificationDetails(
    'focus_alerts', 'Focus alerts',
    channelDescription: 'Pomodoro phase changes and completed goals',
    importance: Importance.high, priority: Priority.high,
  );

  // Stable id spaces so reschedules can't collide.
  static const _habitBase = 10000;
  static const _billBase = 20000;
  static const _focusOngoingId = 1;
  static const _focusPhaseId = 2;

  Future<void> init() async {
    if (_ready || !supportsNotifications) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // keep default UTC location — reminders still fire, possibly offset
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Recompute the full schedule: next 7 days of habit reminders plus the
  /// next occurrence of every bill (due day + 1 day before, at 09:00).
  Future<void> rescheduleAll(List<Habit> habits, List<Bill> bills) async {
    if (!supportsNotifications) return;
    if (!_ready) await init();
    // Clear only scheduled reminders; leave the ongoing focus chip alone.
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _habitBase) await _plugin.cancel(p.id);
    }

    var id = _habitBase;
    final now = DateTime.now();
    for (final habit in habits.where((h) => h.reminderTime != null && !h.archived)) {
      final parts = habit.reminderTime!.split(':');
      final hour = int.tryParse(parts[0]) ?? 9;
      final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      for (var i = 0; i < 7; i++) {
        final day = today.add(Duration(days: i));
        if (!habitDueOn(habit, day)) continue;
        final at = DateTime(day.year, day.month, day.day, hour, minute);
        if (at.isBefore(now)) continue;
        await _zonedSchedule(
          id++, habit.title,
          habitTargetLabel(habit).isEmpty
              ? 'Time for your habit'
              : 'Goal: ${habitTargetLabel(habit)}',
          at, _habitChannel,
        );
      }
    }

    id = _billBase;
    for (final bill in bills.where((b) => !b.archived)) {
      final due = parseDayKey(bill.nextDue);
      final onDue = DateTime(due.year, due.month, due.day, 9);
      final dayBefore = onDue.subtract(const Duration(days: 1));
      if (dayBefore.isAfter(now)) {
        await _zonedSchedule(
            id++, bill.name, 'Due tomorrow', dayBefore, _billChannel);
      }
      if (onDue.isAfter(now)) {
        await _zonedSchedule(id++, bill.name, 'Due today', onDue, _billChannel);
      }
    }
  }

  Future<void> _zonedSchedule(int id, String title, String body, DateTime at,
      AndroidNotificationDetails channel) {
    return _plugin.zonedSchedule(
      id, title, body,
      tz.TZDateTime.from(at, tz.local),
      NotificationDetails(android: channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  // -- focus ----------------------------------------------------------------

  Future<void> showFocusOngoing(String title, DateTime startedAt) async {
    if (!supportsNotifications) return;
    if (!_ready) await init();
    await _plugin.show(
      _focusOngoingId, title, 'Focus session running',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _focusChannel.channelId, _focusChannel.channelName,
          channelDescription: _focusChannel.channelDescription,
          importance: Importance.low, priority: Priority.low,
          ongoing: true, autoCancel: false,
          usesChronometer: true, showWhen: true,
          when: startedAt.millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Future<void> cancelFocusOngoing() async {
    if (!supportsNotifications) return;
    await _plugin.cancel(_focusOngoingId);
  }

  /// Fires even if the app is killed mid-phase.
  Future<void> schedulePhaseEnd(String title, String body, DateTime at) async {
    if (!supportsNotifications) return;
    if (!_ready) await init();
    await _plugin.cancel(_focusPhaseId);
    if (at.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      _focusPhaseId, title, body,
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(android: _focusAlertChannel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelPhaseEnd() async {
    if (!supportsNotifications) return;
    await _plugin.cancel(_focusPhaseId);
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
