/// Validates the optional YouTube link on a song.
///
/// Only real YouTube hosts are accepted. Anything else — including a general
/// web page that merely mentions YouTube — is rejected before it can be saved
/// locally or published.
const _allowedHosts = <String>{
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
  'www.youtu.be',
};

/// Returns true for an empty value or a YouTube URL on an allowed host.
bool isValidYouTubeLink(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return true;

  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return _allowedHosts.contains(uri.host.toLowerCase());
}

/// Form-field validator with a consistent, readable message.
String? validateYouTubeLink(String? value) {
  if (isValidYouTubeLink(value ?? '')) return null;
  return 'Use a youtube.com or youtu.be link.';
}
