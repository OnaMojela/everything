import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/sync/sync_providers.dart';
import '../../data/sync/sync_service.dart';

/// Account and sync controls. Renders nothing when the build has no Supabase
/// credentials, so an offline-only build shows no dead switches.
class SyncSection extends ConsumerWidget {
  const SyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(syncAvailableProvider)) return const SizedBox.shrink();

    final user = ref.watch(authUserProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Sync'),
        AppCard(
          child: user == null ? const _SignedOut() : _SignedIn(user: user),
        ),
      ],
    );
  }
}

class _SignedOut extends ConsumerStatefulWidget {
  const _SignedOut();

  @override
  ConsumerState<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends ConsumerState<_SignedOut> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider)!.signInWithGoogle();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sync across your devices', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Sign in to keep your habits, tasks and finances the same on every '
          'device. Everything stays on this device too, so the app keeps '
          'working offline.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Tokens.s12),
        FilledButton.icon(
          onPressed: _busy ? null : _signIn,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: const Text('Continue with Google'),
        ),
        if (_error != null) ...[
          const SizedBox(height: Tokens.s8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _SignedIn extends ConsumerWidget {
  final User user;
  const _SignedIn({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(syncStatusProvider).valueOrNull ?? const SyncStatus();
    final pending = ref.watch(pendingChangesProvider).valueOrNull ?? 0;

    final email = user.email ?? user.userMetadata?['email'] as String? ?? '';
    final name = user.userMetadata?['full_name'] as String?;
    // Deliberately not loading `avatar_url`: the web build sets
    // Cross-Origin-Embedder-Policy: require-corp so the database can use OPFS,
    // and Google's avatar CDN does not send the CORP header that would let the
    // image through. An initial always renders.
    final initial = (name ?? email).trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            child: initial.isEmpty
                ? const Icon(Icons.person_rounded)
                : Text(initial.characters.first.toUpperCase()),
          ),
          title: Text(name ?? email),
          subtitle: name == null ? null : Text(email),
        ),
        const Divider(height: Tokens.s24),
        Row(
          children: [
            _StatusDot(status: status, pending: pending),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: Text(
                _statusLine(status, pending),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (status.error != null) ...[
          const SizedBox(height: Tokens.s8),
          Text(
            _friendlyError(status.error!),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: Tokens.s12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: status.isSyncing
                  ? null
                  : () => ref.read(syncServiceProvider)!.sync().catchError((_) {
                        // Surfaced through SyncStatus.error just above.
                      }),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Sync now'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _confirmSignOut(context, ref, pending),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ],
    );
  }

  String _statusLine(SyncStatus status, int pending) {
    if (status.stage == SyncStage.pushing) return 'Uploading changes…';
    if (status.stage == SyncStage.pulling) return 'Downloading changes…';
    if (pending > 0) {
      return '$pending change${pending == 1 ? '' : 's'} waiting to upload';
    }
    final at = status.lastSyncedAt;
    if (at == null) return 'Not synced yet';
    return 'Last synced ${DateFormat.MMMd().add_jm().format(at)}';
  }

  /// Sync errors are mostly network weather. Say so plainly instead of
  /// showing a stack trace to someone who just wanted their tasks.
  String _friendlyError(Object error) {
    if (error is AuthException) {
      return 'Sign-in expired. Sign out and back in to resume syncing.';
    }
    if (error is PostgrestException) {
      return 'The server rejected a change (${error.code ?? 'error'}). '
          'It will be retried.';
    }
    return "Couldn't reach the server. Your changes are saved on this device "
        'and will upload when you are back online.';
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    int pending,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          pending > 0
              ? 'You have $pending change${pending == 1 ? '' : 's'} that '
                  "haven't uploaded yet. They will be uploaded first, then "
                  'this device will be cleared. Your data stays in your '
                  'account.'
              : 'This device will be cleared. Your data stays in your account '
                  'and comes back when you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final sync = ref.read(syncServiceProvider)!;

    // Give unsent work a chance to reach the server before the local copy is
    // discarded. If it cannot, say so and keep the data rather than losing it.
    if (pending > 0) {
      try {
        await sync.sync();
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
            "Couldn't upload your latest changes — still signed in so nothing "
            'is lost. Try again when you have a connection.',
          ),
        ));
        return;
      }
    }

    await ref.read(authServiceProvider)!.signOut();
    await ref.read(syncServiceProvider)!.db.wipeLocalData();
    messenger.showSnackBar(
      const SnackBar(content: Text('Signed out. This device has been cleared.')),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final SyncStatus status;
  final int pending;
  const _StatusDot({required this.status, required this.pending});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status.isSyncing) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final color = status.error != null
        ? scheme.error
        : pending > 0
            ? scheme.tertiary
            : scheme.primary;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
