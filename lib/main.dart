import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/services/widget_sync_service.dart';
import 'data/providers.dart';
import 'data/sync/sync_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restores an existing session before the first frame, so a signed-in user
  // never sees the app flash through its signed-out state.
  await initSupabase();
  final container = ProviderContainer();

  final repo = container.read(repoProvider);
  // Unfinished tasks roll forward to today; standing orders post themselves.
  repo.rolloverTasks();
  repo.postDueRecurringTransactions();

  // Keep scheduled reminders in sync with habits and bills, debounced so a
  // burst of edits reschedules once.
  final notifications = container.read(notificationServiceProvider);
  notifications.init();
  Timer? debounce;
  void requestReschedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () {
      final habits = container.read(habitsProvider).valueOrNull;
      final bills = container.read(billsProvider).valueOrNull;
      if (habits != null && bills != null) {
        notifications.rescheduleAll(habits, bills);
      }
    });
  }

  container.listen(habitsProvider, (_, _) => requestReschedule());
  container.listen(billsProvider, (_, _) => requestReschedule());

  // Mirror today's habits into the home-screen widget.
  WidgetSyncService.attach(container);

  // Cross-device sync, if this build has backend credentials. Runs on sign-in,
  // on resume and on a slow timer; a signed-out app is untouched by it.
  container.read(syncServiceProvider)?.loadPersistedStatus();
  SyncCoordinator(container).start();

  runApp(UncontrolledProviderScope(container: container, child: const EverythingApp()));
}
