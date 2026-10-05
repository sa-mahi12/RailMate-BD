import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/board/post/relative_time.dart';

/// V4 P20: honest relative timestamps for board posts. Pure Dart, injected
/// clock — no wall-clock dependency, no Flutter binding.
void main() {
  final DateTime now = DateTime(2026, 10, 4, 12, 0);

  DateTime ago({int? days, int? hours, int? minutes, int? seconds}) {
    return now.subtract(
      Duration(
        days: days ?? 0,
        hours: hours ?? 0,
        minutes: minutes ?? 0,
        seconds: seconds ?? 0,
      ),
    );
  }

  group('formatRelativeTime', () {
    test('null renders nothing (caller shows no timestamp)', () {
      expect(formatRelativeTime(null, now: now), '');
    });

    test('sub-minute ages read as just now', () {
      expect(formatRelativeTime(now, now: now), 'just now');
      expect(formatRelativeTime(ago(seconds: 30), now: now), 'just now');
      expect(formatRelativeTime(ago(seconds: 59), now: now), 'just now');
    });

    test('minutes, hours and days buckets', () {
      expect(formatRelativeTime(ago(minutes: 1), now: now), '1m ago');
      expect(formatRelativeTime(ago(minutes: 59), now: now), '59m ago');
      expect(formatRelativeTime(ago(hours: 1), now: now), '1h ago');
      expect(formatRelativeTime(ago(hours: 23), now: now), '23h ago');
      expect(formatRelativeTime(ago(days: 1), now: now), '1d ago');
      expect(formatRelativeTime(ago(days: 6, hours: 23), now: now), '6d ago');
    });

    test('a week or older falls back to an absolute date', () {
      expect(
        formatRelativeTime(DateTime(2026, 9, 20, 10, 0), now: now),
        '20 Sep 2026',
      );
      expect(
        formatRelativeTime(DateTime(2025, 12, 25, 8, 0), now: now),
        '25 Dec 2025',
      );
    });

    test('clock skew into the future is clamped, never negative', () {
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });

    test('exactly at a bucket boundary moves up, not down', () {
      expect(formatRelativeTime(ago(minutes: 60), now: now), '1h ago');
      expect(formatRelativeTime(ago(hours: 24), now: now), '1d ago');
      expect(formatRelativeTime(ago(days: 7), now: now), '27 Sep 2026');
    });
  });

  group('formatAbsoluteDate', () {
    test('renders day, short month and year for every month', () {
      const List<String> months = <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          formatAbsoluteDate(DateTime(2026, month, 9)),
          '9 ${months[month - 1]} 2026',
        );
      }
      expect(formatAbsoluteDate(DateTime(2026, 3, 9)), '9 Mar 2026');
    });
  });
}
