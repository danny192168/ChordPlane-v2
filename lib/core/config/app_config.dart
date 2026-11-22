/// Compile-time configuration for cloud services.
///
/// Supabase credentials are injected with `--dart-define` so the app stays
/// fully functional (local-only) without them:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
/// ```
///
/// Locally, prefer `tool/run_dev.sh`, which reads the same values from
/// `dart_defines.json` (gitignored; copy `dart_defines.example.json`). Because
/// these are compile-time constants, hot reload cannot switch cloud features
/// on — the app has to be rebuilt and reinstalled.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// True when cloud sharing is compiled in.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Set at boot when [supabaseUrl]/[supabaseAnonKey] are present but
  /// initialization failed (e.g. malformed URL). Surfaced in the UI so a
  /// misconfigured build cannot masquerade as a network hang.
  static String? supabaseInitError;

  /// Where server-backed share links live. Kept as one constant so moving to
  /// another domain later is a redirect, not a broken-link hunt.
  static const String shareHost = 'https://chordplane.citcs.site';

  /// Google OAuth client IDs. Public values, injected at build time so debug
  /// and release fingerprints can share one codebase:
  ///
  /// ```sh
  /// flutter run \
  ///   --dart-define=GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com \
  ///   --dart-define=GOOGLE_IOS_CLIENT_ID=...apps.googleusercontent.com
  /// ```
  ///
  /// The web client ID doubles as `serverClientId` on Android (no
  /// google-services.json is needed); the iOS client ID is only required on
  /// iOS, where its reversed form must also appear as a URL scheme in
  /// `Info.plist`.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// True when native Google sign-in has enough configuration to be offered.
  /// Android only needs the web client ID; on iOS the URL scheme is verified
  /// by Google itself at runtime.
  static bool get hasGoogleSignIn => googleWebClientId.isNotEmpty;

  /// Where Supabase sends people after they confirm an email. The static
  /// `/auth/confirm` page forwards the code back into the app and gives
  /// desktop readers a fallback.
  static String get emailConfirmUrl => '$shareHost/auth/confirm';

  /// Deep link Supabase redirects to after a successful Google sign-in.
  static const String authCallbackUrl = 'chordplane://auth-callback';

  /// Deep link Supabase redirects to from a password-reset email.
  static const String passwordResetUrl = 'chordplane://reset-password';
}
