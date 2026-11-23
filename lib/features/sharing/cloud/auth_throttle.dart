import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many wrong passwords one device may try for one address before the app
/// starts making the person wait.
const int freePasswordAttempts = 3;

/// Waits applied from the fourth wrong password onward. The point is to make
/// scripted guessing tedious while somebody who mistyped a password waits a
/// few seconds, not minutes. The last entry is the cap.
const List<Duration> passwordBackoff = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
];

/// `null` means the attempt is still free; otherwise how long to wait.
Duration? passwordBackoffFor(int failures) {
  if (failures <= freePasswordAttempts) return null;
  final index = (failures - freePasswordAttempts - 1).clamp(
    0,
    passwordBackoff.length - 1,
  );
  return passwordBackoff[index];
}

/// The throttle state for one address at one moment.
class AuthLockout {
  const AuthLockout({
    required this.failures,
    required this.lockedUntil,
    required this.now,
  });

  final int failures;
  final DateTime? lockedUntil;
  final DateTime now;

  bool get isLocked => lockedUntil != null && lockedUntil!.isAfter(now);

  Duration get remaining =>
      isLocked ? lockedUntil!.difference(now) : Duration.zero;
}

/// A local, per-device brake on password attempts.
///
/// This is deliberately *not* the security boundary: anyone who talks to the
/// API directly can ignore it. Supabase Auth's own per-IP limiter is the only
/// server-side gate on the Free plan, and that is shared across every account
/// behind the same address. What this does is make the app itself stop
/// volunteering guesses, survive a restart, and explain the wait instead of
/// showing the same "wrong password" forever.
///
/// State is stored per normalised email so two accounts on one device are
/// throttled independently, and mirrored in memory so the UI can ask for the
/// current lockout without waiting on disk.
class AuthThrottle {
  AuthThrottle({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _AttemptRecord> _cache = {};

  static String _failuresKey(String email) =>
      'auth.attempts.failures.${_normalise(email)}';
  static String _untilKey(String email) =>
      'auth.attempts.until.${_normalise(email)}';

  static String _normalise(String email) => email.trim().toLowerCase();

  /// Reads the persisted state for [email], hydrating the in-memory mirror on
  /// first use. Storage failures are treated as "no state" rather than thrown:
  /// a broken preferences plugin must not block signing in.
  Future<AuthLockout> load(String email) async {
    final key = _normalise(email);
    var record = _cache[key] ?? const _AttemptRecord();
    if (!_cache.containsKey(key)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        record = _AttemptRecord(
          failures: prefs.getInt(_failuresKey(key)) ?? 0,
          lockedUntilMs: prefs.getInt(_untilKey(key)) ?? 0,
        );
      } catch (_) {
        // Keep the empty record; the app still works, it just forgets.
      }
      _cache[key] = record;
    }
    return _lockout(record);
  }

  /// Counts one failed attempt and returns the resulting state.
  ///
  /// [penalty] overrides the computed backoff, so a server 429 can impose its
  /// own window instead of the local schedule.
  Future<AuthLockout> recordFailure(String email, {Duration? penalty}) async {
    final key = _normalise(email);
    final previous = (await load(key)).failures;
    final failures = previous + 1;
    final delay = penalty ?? passwordBackoffFor(failures);
    final record = _AttemptRecord(
      failures: failures,
      lockedUntilMs: delay == null
          ? 0
          : _clock().add(delay).millisecondsSinceEpoch,
    );
    _cache[key] = record;
    await _persist(key, record);
    return _lockout(record);
  }

  /// Forgets the failures for [email]; called after a successful sign-in so a
  /// legitimate member is never penalised for earlier typos.
  Future<void> recordSuccess(String email) async {
    final key = _normalise(email);
    _cache.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_failuresKey(key));
      await prefs.remove(_untilKey(key));
    } catch (_) {
      // Nothing to do; the in-memory entry is already cleared.
    }
  }

  AuthLockout _lockout(_AttemptRecord record) {
    final now = _clock();
    return AuthLockout(
      failures: record.failures,
      lockedUntil: record.lockedUntilMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(record.lockedUntilMs),
      now: now,
    );
  }

  Future<void> _persist(String key, _AttemptRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (record.lockedUntilMs <= 0) {
        await prefs.remove(_untilKey(key));
      } else {
        await prefs.setInt(_untilKey(key), record.lockedUntilMs);
      }
      await prefs.setInt(_failuresKey(key), record.failures);
    } catch (_) {
      // The in-memory mirror still throttles this session.
    }
  }
}

class _AttemptRecord {
  const _AttemptRecord({this.failures = 0, this.lockedUntilMs = 0});

  final int failures;
  final int lockedUntilMs;
}

/// Shared throttle for the whole app, so a lockout started in the sign-in sheet
/// is still in force after the sheet is dismissed and reopened.
final authThrottleProvider = Provider<AuthThrottle>((ref) => AuthThrottle());
