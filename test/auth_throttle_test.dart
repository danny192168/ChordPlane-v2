import 'package:chord_plane/features/sharing/cloud/auth_throttle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The throttle is the local half of the brute-force story, so its schedule,
/// persistence and reset behaviour are worth pinning down without a UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late AuthThrottle throttle;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 1, 1, 12);
    throttle = AuthThrottle(clock: () => now);
  });

  test('the first three attempts are free', () async {
    for (var attempt = 1; attempt <= freePasswordAttempts; attempt++) {
      final lockout = await throttle.recordFailure('a@example.com');
      expect(lockout.isLocked, isFalse, reason: 'attempt $attempt');
    }
  });

  test('the wait grows from the fourth failure and caps out', () async {
    for (var attempt = 1; attempt <= freePasswordAttempts; attempt++) {
      await throttle.recordFailure('a@example.com');
    }

    final waits = <Duration>[];
    for (var attempt = 0; attempt < passwordBackoff.length + 2; attempt++) {
      final lockout = await throttle.recordFailure('a@example.com');
      waits.add(lockout.remaining);
    }

    expect(waits.take(passwordBackoff.length), passwordBackoff);
    expect(waits.last, passwordBackoff.last);
  });

  test('the lock lifts when the clock passes it', () async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await throttle.recordFailure('a@example.com');
    }
    expect((await throttle.load('a@example.com')).isLocked, isTrue);

    now = now.add(const Duration(seconds: 6));

    final later = await throttle.load('a@example.com');
    expect(later.isLocked, isFalse);
    expect(later.failures, 4);
  });

  test('a server 429 can impose its own window', () async {
    final lockout = await throttle.recordFailure(
      'a@example.com',
      penalty: const Duration(minutes: 1),
    );

    expect(lockout.isLocked, isTrue);
    expect(lockout.remaining, const Duration(minutes: 1));
  });

  test('state survives a new throttle instance', () async {
    await throttle.recordFailure('a@example.com');

    final restarted = AuthThrottle(clock: () => now);
    final lockout = await restarted.load('a@example.com');
    expect(lockout.failures, 1);
  });

  test('addresses are normalised and throttled separately', () async {
    await throttle.recordFailure('  A@Example.com ');

    expect((await throttle.load('a@example.com')).failures, 1);
    expect((await throttle.load('b@example.com')).failures, 0);
  });

  test('a successful sign-in forgets the failures', () async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await throttle.recordFailure('a@example.com');
    }
    await throttle.recordSuccess('a@example.com');

    final lockout = await throttle.load('a@example.com');
    expect(lockout.failures, 0);
    expect(lockout.isLocked, isFalse);
  });
}
