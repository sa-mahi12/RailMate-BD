import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/home/home_display_name.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/search/home/home_greeting.dart';

void main() {
  group('P10 daypart', () {
    test('morning/afternoon/evening/night buckets are real local hours', () {
      expect(daypartForHour(5), Daypart.morning);
      expect(daypartForHour(11), Daypart.morning);
      expect(daypartForHour(12), Daypart.afternoon);
      expect(daypartForHour(16), Daypart.afternoon);
      expect(daypartForHour(17), Daypart.evening);
      expect(daypartForHour(21), Daypart.evening);
      expect(daypartForHour(22), Daypart.night);
      expect(daypartForHour(0), Daypart.night);
      expect(daypartForHour(4), Daypart.night);
    });

    test('no greeting is hardcoded to a single daypart', () {
      final Set<String> lines = <String>{
        for (int hour = 0; hour < 24; hour++)
          homeGreeting(now: DateTime(2026, 10, 2, hour), displayName: 'Nabila'),
      };
      // Real dayparts vary the salutation; a hardcoded greeting would collapse
      // this set to one element.
      expect(lines.length, greaterThan(2));
      expect(lines, contains('Good morning, Nabila'));
      expect(lines, contains('Good afternoon, Nabila'));
      expect(lines, contains('Good evening, Nabila'));
    });

    test('night salutation is a greeting, not a farewell', () {
      expect(daypartSalutation(Daypart.night), 'Hello');
      expect(
        signedInGreeting(now: DateTime(2026, 10, 2, 23), displayName: 'Nabila'),
        'Hello, Nabila',
      );
    });

    test('signed out falls back to a neutral greeting (no invented name)', () {
      expect(
        homeGreeting(now: DateTime(2026, 10, 2, 9), displayName: null),
        signedOutGreeting,
      );
      expect(
        homeGreeting(now: DateTime(2026, 10, 2, 9), displayName: '   '),
        signedOutGreeting,
      );
    });

    test('blank display name still shows the daypart salutation', () {
      expect(
        signedInGreeting(now: DateTime(2026, 10, 2, 9), displayName: '  '),
        'Good morning',
      );
    });
  });

  group('P10 display name', () {
    const AuthUser named = AuthUser(
      id: 'u1',
      email: 'a@b.co',
      emailConfirmed: true,
      fullName: 'Nabila Rahman',
    );
    const AuthUser usernameOnly = AuthUser(
      id: 'u2',
      email: 'c@d.co',
      emailConfirmed: true,
      username: 'nabila',
    );
    const AuthUser bare = AuthUser(
      id: 'u3',
      email: 'e@f.co',
      emailConfirmed: true,
    );

    test('full name, then @username, then null (never the email)', () {
      expect(homeDisplayName(named), 'Nabila Rahman');
      expect(homeDisplayName(usernameOnly), '@nabila');
      expect(homeDisplayName(bare), isNull);
      expect(homeDisplayName(null), isNull);
    });
  });
}
