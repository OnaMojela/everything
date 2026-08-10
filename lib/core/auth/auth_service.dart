import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Google sign-in on top of Supabase auth.
///
/// The two platforms take genuinely different routes and neither substitutes
/// for the other:
///
/// * **Web** hands off to Google with a full-page redirect. A popup would be
///   blocked by the cross-origin isolation headers the database needs for
///   OPFS, so the redirect is not just a preference — it is the flow that
///   works.
/// * **Android and iOS** use the native account picker, which signs in with
///   accounts already on the device and never opens a browser. It returns a
///   Google ID token that Supabase exchanges for a session.
class AuthService {
  final SupabaseClient _supabase;

  AuthService(this._supabase);

  User? get currentUser => _supabase.auth.currentUser;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // Return to wherever the app is actually served from, so the same
        // build works on a Vercel preview URL and on the production domain.
        redirectTo: Uri.base.origin,
      );
      // The page navigates away; the session is restored on the way back.
      return;
    }
    await _nativeGoogleSignIn();
  }

  Future<void> _nativeGoogleSignIn() async {
    if (SupabaseConfig.googleWebClientId.isEmpty) {
      throw const AuthException(
        'Google sign-in is not configured for this build '
        '(missing GOOGLE_WEB_CLIENT_ID).',
      );
    }

    final google = GoogleSignIn.instance;
    await google.initialize(
      // Supabase validates that the ID token was issued for its own client id,
      // which is the *web* one even on Android.
      serverClientId: SupabaseConfig.googleWebClientId,
      clientId: SupabaseConfig.googleIosClientId.isEmpty
          ? null
          : SupabaseConfig.googleIosClientId,
    );

    // Try the silent path first so a returning user is not asked to pick an
    // account they already chose; fall back to the picker.
    var account = await google.attemptLightweightAuthentication();
    if (account == null) {
      if (!google.supportsAuthenticate()) {
        throw const AuthException(
          'Google sign-in is not available on this platform.',
        );
      }
      account = await google.authenticate();
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token.');
    }

    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email', 'profile']);

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization?.accessToken,
    );
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      // Also clear the native picker's cached choice, so signing out and
      // straight back in lets the user pick a different account.
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Never block signing out of the app because the Google plugin was
        // not initialised on this run.
      }
    }
    await _supabase.auth.signOut();
  }
}
