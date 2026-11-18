/// Configuration for the public web viewer (Option A deploy).
///
/// These values are safe to commit: the publishable key is designed for
/// public, unauthenticated clients, and row-level security on the server
/// only exposes active, unrevoked shares — the token in the URL is the
/// secret, not this key.
class WebViewerConfig {
  const WebViewerConfig._();

  /// Public host for the share viewer and the download page.
  static const String siteUrl = 'https://chordplane.citcs.site';

  /// Download page for the Android build (iOS is not published yet).
  static String get downloadUrl => '$siteUrl/download';

  static const String supabaseUrl = 'https://eweppodjncodtsiljvak.supabase.co';

  /// Publishable (anon) key for REST reads of `shared_bundles`.
  static const String supabasePublishableKey =
      'sb_publishable_ikLjo_Uua2EXV5p2rffR2Q_-oOSvF34';
}
