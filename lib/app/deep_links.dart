import '../features/sharing/cpl.dart';
import '../core/config/app_config.dart';

/// Maps an incoming deep link or platform route onto an app location.
///
/// Cold-start links arrive as either the raw path (`/c/<code>`) or the full
/// `chordplane://c/<code>` / `https://…/c/<code>` URI depending on the
/// platform, so normalise both here. Server-backed links use `/s/<token>`
/// on the share host or the same path under the custom scheme.
String routeForIncomingLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return '/';

  final uri = Uri.tryParse(input);
  final isCustomScheme = uri != null && uri.scheme == CplFormat.customScheme;
  final isAppHost =
      uri != null &&
      (uri.host == 'chordplane.app' ||
          uri.host == Uri.parse(AppConfig.shareHost).host);
  if (isCustomScheme || isAppHost) {
    if (isCustomScheme) {
      // Supabase redirects recovery and confirmation links to the custom
      // scheme; neither carries a share code.
      final target = uri.host.isNotEmpty
          ? uri.host
          : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
      if (target == 'reset-password') return '/set-new-password';
      if (target == 'auth-callback') return '/';
    }
    // A universal link straight to the web confirmation page should land in
    // the app at home; the page itself forwards the code to the scheme.
    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 'auth' &&
        uri.pathSegments[1] == 'confirm') {
      return '/';
    }
    final token = CplFormat.extractServerToken(input);
    if (token != null) return '/s/$token';
    final code = CplBundle.extractShareCode(input);
    if (code != null) return '/c/$code';
    if (uri.pathSegments.isNotEmpty) {
      return '/${uri.pathSegments.join('/')}';
    }
  }
  return input.startsWith('/') ? input : '/$input';
}

/// True when [raw] is a Supabase auth redirect (email confirmation or
/// password recovery) rather than a share link.
bool isAuthDeepLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;
  if (uri.scheme == CplFormat.customScheme) {
    final target = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    return target == 'reset-password' || target == 'auth-callback';
  }
  final isAppHost =
      uri.host == 'chordplane.app' ||
      uri.host == Uri.parse(AppConfig.shareHost).host;
  if (!isAppHost) return false;
  return uri.pathSegments.length >= 2 &&
      uri.pathSegments[0] == 'auth' &&
      uri.pathSegments[1] == 'confirm';
}
