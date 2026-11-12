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
}
