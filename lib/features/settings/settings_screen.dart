import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_support.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/lock_gate.dart';
import '../../core/services/notification_capture.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/sync/sync_providers.dart';
import 'sync_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s4, Tokens.s16, Tokens.s32),
        children: [
          const SectionHeader('Appearance'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: theme.textTheme.titleSmall),
                const SizedBox(height: Tokens.s8),
                SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: AppThemeMode.system, label: Text('Auto')),
                    ButtonSegment(value: AppThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: AppThemeMode.dark, label: Text('Dark')),
                    ButtonSegment(value: AppThemeMode.oled, label: Text('OLED')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) =>
                      notifier.update((x) => x.copyWith(themeMode: s.first)),
                ),
                const SizedBox(height: Tokens.s16),
                Text('Accent color', style: theme.textTheme.titleSmall),
                const SizedBox(height: Tokens.s8),
                Wrap(
                  spacing: Tokens.s8,
                  runSpacing: Tokens.s8,
                  children: [
                    for (var i = 0; i < accentPalette.length; i++)
                      GestureDetector(
                        onTap: () => notifier.update((x) => x.copyWith(accentIndex: i)),
                        child: AnimatedContainer(
                          duration: Tokens.fast,
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accentPalette[i].color,
                            shape: BoxShape.circle,
                            border: settings.accentIndex == i
                                ? Border.all(color: theme.colorScheme.onSurface, width: 2.5)
                                : null,
                          ),
                          child: settings.accentIndex == i
                              ? const Icon(Icons.check, color: Colors.white, size: 20)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.s8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compact density'),
                  subtitle: const Text('Fit more on screen'),
                  value: settings.compactMode,
                  onChanged: (v) => notifier.update((x) => x.copyWith(compactMode: v)),
                ),
              ],
            ),
          ),
          const SectionHeader('Modules'),
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Productivity'),
                  subtitle: const Text('Habits, tasks, planner, focus'),
                  value: settings.showProductivity,
                  onChanged: settings.showFinance
                      ? (v) => notifier.update((x) => x.copyWith(showProductivity: v))
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Finance'),
                  subtitle: const Text('Accounts, budgets, bills, goals'),
                  value: settings.showFinance,
                  onChanged: settings.showProductivity
                      ? (v) => notifier.update((x) => x.copyWith(showFinance: v))
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: Tokens.s4),
                  child: Text(
                    'Hide a module you don\'t use — navigation and the dashboard adapt automatically.',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (supportsAppLock) ...[
            const SectionHeader('Security'),
            AppCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('App lock'),
                subtitle: const Text('Fingerprint, face or device PIN on open'),
                value: settings.appLockEnabled,
                onChanged: (v) async {
                  final ok = await authenticateUser(
                      v ? 'Confirm to enable app lock' : 'Confirm to disable app lock');
                  if (ok) notifier.update((x) => x.copyWith(appLockEnabled: v));
                },
              ),
            ),
          ],
          const SectionHeader('Finance'),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.category_rounded),
                  title: const Text('Categories'),
                  subtitle: const Text('Add, edit and reorder spending categories'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/categories'),
                ),
                if (supportsNotificationCapture)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inbox_rounded),
                    title: const Text('Transaction inbox'),
                    subtitle: const Text('Review transactions read from bank notifications'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/inbox'),
                  ),
              ],
            ),
          ),
          if (supportsNotificationCapture) ...[
            const SectionHeader('Automatic transaction capture'),
            const _CaptureSettingsCard(),
          ],
          const SyncSection(),
          const SectionHeader('Your data'),
          const _BackupCard(),
          const SectionHeader('Preferences'),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Your name'),
                  subtitle: Text(
                      settings.userName.isEmpty ? 'Not set' : settings.userName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editText(
                    context,
                    title: 'Your name',
                    initial: settings.userName,
                    onSave: (v) => notifier.update((x) => x.copyWith(userName: v)),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Currency symbol'),
                  subtitle: Text(settings.currencySymbol),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editText(
                    context,
                    title: 'Currency symbol',
                    initial: settings.currencySymbol,
                    onSave: (v) => notifier
                        .update((x) => x.copyWith(currencySymbol: v.isEmpty ? 'R' : v)),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Week starts on Monday'),
                  value: settings.weekStartsMonday,
                  onChanged: (v) =>
                      notifier.update((x) => x.copyWith(weekStartsMonday: v)),
                ),
              ],
            ),
          ),
          const SectionHeader('About'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Everything', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Consumer(
                  builder: (context, ref, _) {
                    // The old copy promised the data never leaves the device.
                    // That is still true right up until someone signs in, so
                    // the claim now follows the account rather than outliving
                    // it.
                    final signedIn =
                        ref.watch(authUserProvider).valueOrNull != null;
                    final where = isWeb ? 'this browser' : 'this device';
                    return Text(
                      signedIn
                          ? 'Your productivity and finances, in one calm '
                              'place. Stored in $where and synced to your '
                              'account so every device matches.'
                          : 'Your productivity and finances, in one calm '
                              'place. No account · everything is stored in '
                              '$where and never sent anywhere.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editText(BuildContext context,
      {required String title,
      required String initial,
      required ValueChanged<String> onSave}) {
    final ctrl = TextEditingController(text: initial);
    showAppSheet(
      context,
      SheetScaffold(
        title: title,
        actionLabel: 'Save',
        onAction: () {
          onSave(ctrl.text.trim());
          Navigator.pop(context);
        },
        children: [TextField(controller: ctrl, autofocus: true)],
      ),
    );
  }
}

/// Capture toggle plus the Android notification-access permission flow.
class _CaptureSettingsCard extends ConsumerStatefulWidget {
  const _CaptureSettingsCard();

  @override
  ConsumerState<_CaptureSettingsCard> createState() => _CaptureSettingsCardState();
}

class _CaptureSettingsCardState extends ConsumerState<_CaptureSettingsCard>
    with WidgetsBindingObserver {
  bool? hasPermission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user comes back from the system settings screen.
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await ref.read(notificationCaptureProvider).hasPermission();
    if (mounted) setState(() => hasPermission = granted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final capture = ref.read(notificationCaptureProvider);
    final granted = hasPermission ?? false;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything can read notifications from your banking apps to spot '
            'transactions automatically. Only notifications that mention an amount '
            'of money are kept, everything stays on this device, and nothing is '
            'added to your accounts until you confirm it.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Tokens.s12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Capture transactions'),
            subtitle: Text(granted
                ? 'Reading bank notifications'
                : 'Needs notification access'),
            value: settings.captureEnabled && granted,
            onChanged: (v) async {
              if (v && !granted) {
                await _showPermissionDialog();
                return;
              }
              await capture.setEnabled(v);
              await notifier.update((s) => s.copyWith(captureEnabled: v));
            },
          ),
          if (settings.captureEnabled && granted) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save confident matches automatically'),
              subtitle: const Text(
                  'Only when the amount, direction and account are all certain'),
              value: settings.captureAutoConfirm,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(captureAutoConfirm: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trust the balance my bank reports'),
              subtitle: const Text(
                  'Corrects the account to match, so you never reconcile by hand. '
                  'Skipped for credit cards and loans.'),
              value: settings.syncBalanceFromBank,
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(syncBalanceFromBank: v)),
            ),
          ],
          if (!granted)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s4),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Grant notification access'),
                onPressed: _showPermissionDialog,
              ),
            ),
          if (settings.captureMutedPackages.isNotEmpty) ...[
            const SizedBox(height: Tokens.s8),
            Text('Muted apps', style: theme.textTheme.titleSmall),
            const SizedBox(height: Tokens.s4),
            Wrap(
              spacing: Tokens.s8,
              children: [
                for (final pkg in settings.captureMutedPackages)
                  InputChip(
                    label: Text(pkg.split('.').last),
                    onDeleted: () async {
                      final next = [...settings.captureMutedPackages]..remove(pkg);
                      await notifier
                          .update((s) => s.copyWith(captureMutedPackages: next));
                      await capture.setMutedPackages(next);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPermissionDialog() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow notification access'),
        content: const Text(
          'Android will open its Notification access screen. Find "Everything" in '
          'the list and switch it on, then come back here.\n\n'
          'This permission lets the app read notifications while it runs. It only '
          'stores ones that mention money, and never sends anything anywhere.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open settings')),
        ],
      ),
    );
    if (proceed != true) return;

    final capture = ref.read(notificationCaptureProvider);
    // Arm the listener so capture begins the moment access is granted.
    await capture.setEnabled(true);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(captureEnabled: true));
    await capture.openSystemSettings();
  }
}

/// Backup, restore and CSV export.
class _BackupCard extends ConsumerStatefulWidget {
  const _BackupCard();

  @override
  ConsumerState<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<_BackupCard> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isWeb
                ? 'Everything is stored in this browser only. Clearing site data erases it, '
                    'so keep a backup — the file also moves your data to the Android app.'
                : 'Everything is stored on this device only. A backup file is the only way '
                    'to recover it if you lose your phone, and it moves your data to the web app.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Tokens.s12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.save_alt_rounded),
            title: const Text('Back up everything'),
            subtitle: const Text('One file with all your data and settings'),
            enabled: !busy,
            onTap: () => _run(() async {
              final path = await ref
                  .read(backupServiceProvider)
                  .exportBackup(ref.read(settingsProvider));
              return path == null ? null : 'Backup saved';
            }),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export transactions as CSV'),
            subtitle: const Text('Open in Excel, Sheets or Numbers'),
            enabled: !busy,
            onTap: () => _run(() async {
              final path = await ref
                  .read(backupServiceProvider)
                  .exportTransactionsCsv(settings.currencySymbol);
              return path == null ? null : 'Transactions exported';
            }),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_backup_restore_rounded,
                color: theme.colorScheme.error),
            title: const Text('Restore from backup'),
            subtitle: const Text('Replaces everything currently in the app'),
            enabled: !busy,
            onTap: busy ? null : _restore,
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: Tokens.s8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => busy = true);
    try {
      final message = await action();
      if (message != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'Everything currently in the app — habits, tasks, accounts and transactions — '
          'will be replaced by the contents of the backup file.\n\n'
          'This cannot be undone. Consider backing up first.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace my data'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final report = await ref.read(backupServiceProvider).importBackup(
            applySettings: (restored) =>
                ref.read(settingsProvider.notifier).update((_) => restored),
          );
      if (report == null) return null;
      return 'Restored ${report.rows} records';
    });
  }
}
