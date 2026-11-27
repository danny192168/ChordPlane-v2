import 'package:chord_plane/core/utils/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  String age(Duration duration) => relativeTime(
    now.subtract(duration),
    now: now,
  );

  group('relativeTime', () {
    test('uses just now for sub-minute and future timestamps', () {
      expect(age(const Duration(seconds: 30)), 'just now');
      expect(relativeTime(now.add(const Duration(minutes: 2)), now: now),
          'just now');
    });

    test('formats minutes, hours and days', () {
      expect(age(const Duration(minutes: 5)), '5m ago');
      expect(age(const Duration(hours: 2)), '2h ago');
      expect(age(const Duration(days: 3)), '3d ago');
    });

    test('switches to weeks, months and years', () {
      expect(age(const Duration(days: 7)), '1w ago');
      expect(age(const Duration(days: 21)), '3w ago');
      expect(age(const Duration(days: 35)), '1mo ago');
      expect(age(const Duration(days: 400)), '1y ago');
    });

    test('accepts local timestamps', () {
      final local = now.toLocal();
      expect(relativeTime(local, now: now), 'just now');
    });
  });
}
