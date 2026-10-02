/// P10 - dynamic daypart greeting for the Home tab (V4
/// `09_HOME_SEARCH_SPEC.md`).
///
/// Pure daypart logic is separated from the widget so it can be unit tested
/// with an injected clock: no test depends on the wall clock. There is no
/// hardcoded "Good morning" anywhere - the greeting is derived from the real
/// local hour at build time.
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';

/// Local dayparts used by the Home greeting.
enum Daypart {
  /// 05:00-11:59.
  morning,

  /// 12:00-16:59.
  afternoon,

  /// 17:00-21:59.
  evening,

  /// 22:00-04:59 (crossing midnight).
  night,
}

/// Daypart for a local [hour] (0-23). Pure and clock-free.
Daypart daypartForHour(int hour) {
  final int h = hour % 24;
  if (h >= 5 && h < 12) return Daypart.morning;
  if (h >= 12 && h < 17) return Daypart.afternoon;
  if (h >= 17 && h < 22) return Daypart.evening;
  return Daypart.night;
}

/// Daypart of [now] in local time.
Daypart daypartForNow(DateTime now) => daypartForHour(now.hour);

/// Salutation word for [daypart]. Night is a neutral "Hello" because
/// "Good night" is a farewell, not a greeting.
String daypartSalutation(Daypart daypart) {
  switch (daypart) {
    case Daypart.morning:
      return 'Good morning';
    case Daypart.afternoon:
      return 'Good afternoon';
    case Daypart.evening:
      return 'Good evening';
    case Daypart.night:
      return 'Hello';
  }
}

/// Greeting line for a signed-in traveller.
///
/// `Good morning, Nabila` when a [displayName] is known, otherwise the bare
/// daypart salutation. Never fabricates a name.
String signedInGreeting({required DateTime now, required String? displayName}) {
  final String name = (displayName ?? '').trim();
  final String salutation = daypartSalutation(daypartForNow(now));
  return name.isEmpty ? salutation : '$salutation, $name';
}

/// Greeting line used while signed out: neutral, no daypart flattery and no
/// invented name.
const String signedOutGreeting = 'Welcome to RailMate BD';

/// Convenience: greeting for any sign-in state.
String homeGreeting({required DateTime now, required String? displayName}) =>
    (displayName ?? '').trim().isEmpty
    ? signedOutGreeting
    : signedInGreeting(now: now, displayName: displayName);

/// Teal Home header: dynamic greeting line + the main statement.
///
/// [displayName] is the signed-in account's display name (from
/// `AuthState.user`); pass null/blank while signed out and the neutral
/// greeting renders. [now] is injectable for tests only - production passes
/// null so the real local clock is read at build time.
class HomeGreetingHeader extends StatelessWidget {
  final String? displayName;
  final DateTime? now;

  const HomeGreetingHeader({super.key, this.displayName, this.now});

  @override
  Widget build(BuildContext context) {
    final DateTime clock = now ?? DateTime.now();
    final String line = homeGreeting(now: clock, displayName: displayName);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        56,
        AppSpacing.s20,
        AppSpacing.s40 + 24,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadii.headerBottomRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FadeSlideIn(
            duration: AppMotion.standard,
            child: Text(
              line,
              style: const TextStyle(color: AppColors.onPrimary, fontSize: 15),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          FadeSlideIn(
            delay: AppMotion.fast,
            duration: AppMotion.standard,
            child: const Text(
              'Where are you going today?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
