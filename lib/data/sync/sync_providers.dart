import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/supabase_config.dart';
import '../providers.dart';
import 'sync_service.dart';

/// Set once by [initSupabase]. Null when the app was built without backend
/// credentials, which is a supported configuration — the app is offline-first
/// and stays fully usable without an account.
SupabaseClient? _client;

/// Brings up Supabase before the app runs. Safe to call when unconfigured.
///
/// Failure here is deliberately not fatal. This is an offline-first app: a
/// missing network permission, a device with no connection, or a malformed
/// key should cost the user sync, not the whole app. Letting the exception
/// escape would happen before `runApp`, so nothing would ever render and the
/// app would simply crash-loop on launch — which is exactly what a release
/// build without `android.permission.INTERNET` did.
Future<void> initSupabase() async {
  if (!SupabaseConfig.isConfigured) return;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        // Sessions survive restarts, so a phone that has been offline for a
        // week still comes back signed in.
        autoRefreshToken: true,
      ),
    );
    _client = Supabase.instance.client;
  } catch (error, stack) {
    _client = null;
    // The sync UI keys off `syncAvailableProvider`, so it hides itself and
    // the rest of the app carries on exactly as it does offline.
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'everything/sync',
      context: ErrorDescription(
        'initialising Supabase — continuing without sync',
      ),
    ));
  }
}

final supabaseClientProvider = Provider<SupabaseClient?>((ref) => _client);

final syncAvailableProvider =
    Provider<bool>((ref) => ref.watch(supabaseClientProvider) != null);

final authServiceProvider = Provider<AuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AuthService(client);
});

/// The signed-in user, or null. Rebuilds on sign-in, sign-out and token
/// refresh.
final authUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) return Stream.value(null);
  return auth.authStateChanges
      .map((state) => state.session?.user)
      .startWith(auth.currentUser);
});

final syncServiceProvider = Provider<SyncService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final service = SyncService(db: ref.watch(dbProvider), supabase: client);
  ref.onDispose(service.dispose);
  return service;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final sync = ref.watch(syncServiceProvider);
  if (sync == null) return const Stream.empty();
  return sync.statusStream.startWith(sync.status);
});

/// Live count of local edits waiting to be uploaded.
final pendingChangesProvider = StreamProvider<int>((ref) {
  final sync = ref.watch(syncServiceProvider);
  if (sync == null) return Stream.value(0);
  return sync.watchPendingCount();
});

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}

/// Wires sync into the app's lifecycle. It runs when someone signs in, a few
/// seconds after an edit, when the app returns to the foreground, and on a
/// backstop timer while in use.
///
/// Edits are debounced rather than sent one at a time: ticking off six habits
/// should be one upload, not six. The timer is what carries changes made on
/// *another* device, so it bounds how stale this one can be.
class SyncCoordinator with WidgetsBindingObserver {
  final ProviderContainer _container;
  Timer? _periodic;
  Timer? _pushDebounce;
  ProviderSubscription<AsyncValue<User?>>? _authSub;
  ProviderSubscription<AsyncValue<int>>? _pendingSub;
  String? _adoptedUserId;
  DateTime? _firstPendingAt;

  SyncCoordinator(this._container);

  /// Backstop poll, and the only way changes made on another device arrive.
  /// Affordable at this frequency because an idle pull is a single request —
  /// see `SyncService._changedTables`.
  static const pollInterval = Duration(seconds: 90);

  /// How long to wait after an edit before uploading. Long enough that
  /// ticking off six habits in a row is one upload rather than six, short
  /// enough that putting the phone down means the change is already gone.
  static const pushDelay = Duration(seconds: 3);

  /// Cap on how long the debounce may keep deferring. Without it, a long
  /// stretch of continuous editing would postpone the upload indefinitely.
  static const maxPushDelay = Duration(seconds: 20);

  void start() {
    if (!_container.read(syncAvailableProvider)) return;
    WidgetsBinding.instance.addObserver(this);

    _authSub = _container.listen<AsyncValue<User?>>(
      authUserProvider,
      (_, next) => _onUser(next.valueOrNull),
      fireImmediately: true,
    );

    // Upload shortly after an edit rather than waiting for the next poll.
    // The change log already streams a live count, so this is just a debounce
    // on top of bookkeeping the sync engine keeps anyway.
    _pendingSub = _container.listen<AsyncValue<int>>(
      pendingChangesProvider,
      (_, next) => _onPendingChanged(next.valueOrNull ?? 0),
    );

    _periodic = Timer.periodic(pollInterval, (_) => _syncQuietly());
  }

  void _onPendingChanged(int pending) {
    if (pending == 0) {
      _pushDebounce?.cancel();
      _pushDebounce = null;
      _firstPendingAt = null;
      return;
    }

    final now = DateTime.now();
    _firstPendingAt ??= now;

    // Once the oldest unsent edit is old enough, stop deferring and go.
    if (now.difference(_firstPendingAt!) >= maxPushDelay) {
      _pushDebounce?.cancel();
      _pushDebounce = null;
      _firstPendingAt = null;
      _syncQuietly();
      return;
    }

    _pushDebounce?.cancel();
    _pushDebounce = Timer(pushDelay, () {
      _firstPendingAt = null;
      _syncQuietly();
    });
  }

  Future<void> _onUser(User? user) async {
    final sync = _container.read(syncServiceProvider);
    if (sync == null) return;

    if (user == null) {
      _adoptedUserId = null;
      return;
    }
    if (_adoptedUserId == user.id) return;
    _adoptedUserId = user.id;

    await sync.adoptUser(user.id);
    await _syncQuietly();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncQuietly();
  }

  /// Sync failures are expected and unremarkable — a tunnel, a dead hotspot,
  /// an expired token. The status stream carries the error to the settings
  /// screen; nothing here should interrupt what the user is doing.
  Future<void> _syncQuietly() async {
    final sync = _container.read(syncServiceProvider);
    if (sync == null) return;
    if (_container.read(authUserProvider).valueOrNull == null) return;
    try {
      await sync.sync();
    } catch (_) {
      // Already surfaced via SyncStatus.error.
    }
  }

  void dispose() {
    _periodic?.cancel();
    _pushDebounce?.cancel();
    _authSub?.close();
    _pendingSub?.close();
    WidgetsBinding.instance.removeObserver(this);
  }
}
