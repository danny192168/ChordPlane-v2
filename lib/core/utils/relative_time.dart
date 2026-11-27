/// Short, human-friendly age labels for community uploads.
///
/// Kept deliberately tiny and dependency-free: the catalog stores UTC
/// timestamps, and the label only needs to answer "how long ago?" at a glance.
/// Future timestamps (clock skew between device and server) read as "just
/// now" rather than producing a negative age.
String relativeTime(DateTime timestamp, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final seconds = reference.difference(timestamp.toUtc()).inSeconds;
  if (seconds < 60) return 'just now';

  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';

  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h ago';

  final days = hours ~/ 24;
  if (days < 7) return '${days}d ago';

  final weeks = days ~/ 7;
  if (weeks < 5) return '${weeks}w ago';

  final months = days ~/ 30;
  if (months < 12) return '${months}mo ago';

  return '${days ~/ 365}y ago';
}
