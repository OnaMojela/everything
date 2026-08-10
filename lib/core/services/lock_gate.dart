import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../platform/platform_support.dart';
import '../settings/app_settings.dart';
import '../theme/app_theme.dart';

final localAuth = LocalAuthentication();

/// Prompts for the device's biometric/PIN unlock. Returns true when the user
/// authenticated (or the device simply has no lock configured).
Future<bool> authenticateUser(String reason) async {
  if (!supportsAppLock) return true;
  try {
    final supported = await localAuth.isDeviceSupported();
    if (!supported) return true;
    return await localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false, // falls back to device PIN/pattern
        stickyAuth: true,
      ),
    );
  } catch (_) {
    return false;
  }
}

/// Wraps the whole app. When app lock is enabled, the content is covered on
/// launch and every return from background until the user authenticates.
class LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  bool _locked = true;
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeUnlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        ref.read(settingsProvider).appLockEnabled &&
        !_authInFlight) {
      setState(() => _locked = true);
    }
    if (state == AppLifecycleState.resumed && _locked) _maybeUnlock();
  }

  Future<void> _maybeUnlock() async {
    if (!supportsAppLock || !ref.read(settingsProvider).appLockEnabled) {
      if (_locked) setState(() => _locked = false);
      return;
    }
    if (_authInFlight) return;
    _authInFlight = true;
    final ok = await authenticateUser('Unlock Everything');
    _authInFlight = false;
    if (mounted && ok) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        supportsAppLock && ref.watch(settingsProvider.select((s) => s.appLockEnabled));
    if (!enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_rounded,
                        size: 36, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: Tokens.s20),
                  Text('Everything is locked',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: Tokens.s8),
                  Text('Your data stays private on this device',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: Tokens.s24),
                  FilledButton.icon(
                    onPressed: _maybeUnlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
