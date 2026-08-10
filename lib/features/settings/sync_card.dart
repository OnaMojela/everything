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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _creatingAccount = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  /// Set after signing up on a project that requires email confirmation —
  /// nothing is signed in until the emailed link is opened.
  String? _awaitingConfirmation;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authServiceProvider)!;
    await _run(() async {
      if (_creatingAccount) {
        final signedIn = await auth.signUpWithEmail(
          email: _email.text,
          password: _password.text,
        );
        if (!signedIn && mounted) {
          setState(() => _awaitingConfirmation = _email.text.trim());
        }
      } else {
        await auth.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      }
    });
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    await _run(() async {
      await ref.read(authServiceProvider)!.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_awaitingConfirmation case final pending?) {
      return _ConfirmEmailNotice(
        email: pending,
        onBack: () => setState(() => _awaitingConfirmation = null),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
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
          const SizedBox(height: Tokens.s16),
          TextFormField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return 'Enter your email address.';
              // Deliberately loose: the server is the real authority on what
              // a deliverable address is, and clever regexes reject valid ones.
              if (!value.contains('@') || !value.contains('.')) {
                return "That doesn't look like an email address.";
              }
              return null;
            },
          ),
          const SizedBox(height: Tokens.s12),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_showPassword,
            autofillHints: [
              _creatingAccount ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) {
              final value = v ?? '';
              if (value.isEmpty) return 'Enter your password.';
              // Only enforced when creating an account: an existing password
              // shorter than this should still be allowed to sign in.
              if (_creatingAccount && value.length < 6) {
                return 'Use at least 6 characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: Tokens.s16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_creatingAccount ? 'Create account' : 'Sign in'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Tokens.s8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: Tokens.s4),
          Row(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _creatingAccount = !_creatingAccount;
                          _error = null;
                        }),
                child: Text(_creatingAccount
                    ? 'I already have an account'
                    : 'Create an account'),
              ),
              const Spacer(),
              if (!_creatingAccount)
                TextButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: const Text('Forgot password'),
                ),
            ],
          ),
          const Divider(height: Tokens.s24),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(ref.read(authServiceProvider)!.signInWithGoogle),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Continue with Google'),
          ),
        ],
      ),
    );
  }
}

/// Shown after signing up on a project that requires email confirmation.
/// Without this the app would look like it had simply failed — the account
/// exists, but no session starts until the emailed link is opened.
class _ConfirmEmailNotice extends StatelessWidget {
  final String email;
  final VoidCallback onBack;

  const _ConfirmEmailNotice({required this.email, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.mark_email_unread_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: Text('Check your inbox', style: theme.textTheme.titleSmall),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s8),
        Text(
          'We sent a confirmation link to $email. Open it to finish creating '
          'your account, then come back and sign in.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Tokens.s12),
        TextButton(onPressed: onBack, child: const Text('Back to sign in')),
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
