import '../features/sharing/cpl.dart';

/// Maps an incoming deep link or platform route onto an app location.
///
/// Cold-start links arrive as either the raw path (`/c/<code>`) or the full
/// `chordplane://c/<code>` / `https://chordplane.app/c/<code>` URI depending on
/// the platform, so normalise both here.
String routeForIncomingLink(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return '/';

  final uri = Uri.tryParse(input);
  final isCustomScheme = uri != null && uri.scheme == CplFormat.customScheme;
  final isAppHost = uri != null && uri.host == 'chordplane.app';
  if (isCustomScheme || isAppHost) {
    final code = CplBundle.extractShareCode(input);
    if (code != null) return '/c/$code';
    if (uri.pathSegments.isNotEmpty) {
      return '/${uri.pathSegments.join('/')}';
    }
  }
  return input.startsWith('/') ? input : '/$input';
}
