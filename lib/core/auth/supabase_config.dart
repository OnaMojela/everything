/// Supabase and Google credentials, supplied at build time.
///
/// These are compile-time constants rather than a bundled `.env` file so the
/// web build inlines them and there is no extra asset request before the app
/// can talk to the backend.
///
/// All four values are safe to ship in a client: the anon key only grants what
/// row-level security allows, and OAuth client ids are public by design. The
/// service-role key must never appear here.
///
///     flutter build web --release \
///       --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///       --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Google OAuth "Web application" client id. On Android this is passed to
  /// `google_sign_in` as the *server* client id so the ID token it returns is
  /// addressed to Supabase, which is what Supabase verifies it against.
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google OAuth iOS client id. Only needed for an iOS build.
  static const googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Whether the app was built with backend credentials. When false the app
  /// runs exactly as it always has — fully offline, with the sync section
  /// hidden rather than shown as a control that cannot work.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
