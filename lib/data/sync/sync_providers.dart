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

/// Wires sync into the app's lifecycle: it runs when someone signs in, when
/// the app comes back to the foreground, and on a slow timer while in use.
///
/// Deliberately not on every local edit — ticking off six habits should not
/// mean six round trips. Changes queue locally and go out together.
class SyncCoordinator with WidgetsBindingObserver {
  final ProviderContainer _container;
  Timer? _periodic;
  ProviderSubscription<AsyncValue<User?>>? _authSub;
  String? _adoptedUserId;

  SyncCoordinator(this._container);

  static const _interval = Duration(minutes: 5);

  void start() {
    if (!_container.read(syncAvailableProvider)) return;
    WidgetsBinding.instance.addObserver(this);

    _authSub = _container.listen<AsyncValue<User?>>(
      authUserProvider,
      (_, next) => _onUser(next.valueOrNull),
      fireImmediately: true,
    );

    _periodic = Timer.periodic(_interval, (_) => _syncQuietly());
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
    _authSub?.close();
    WidgetsBinding.instance.removeObserver(this);
  }
}
