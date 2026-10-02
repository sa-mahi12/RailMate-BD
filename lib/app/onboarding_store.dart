/// P03 — first-run onboarding persistence (RailMate BD).
///
/// The onboarding-completed flag is deliberately stored **independently of the
/// auth session**: signing out must not replay onboarding, and clearing the
/// session must not reset the flag. Only an explicit app-data clear (or a
/// fresh install) returns the user to onboarding.
///
/// No secrets are stored here — a single boolean flag only.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user has finished the first-run onboarding tour.
abstract interface class OnboardingStore {
  /// True once the user has completed (or skipped) onboarding.
  Future<bool> isCompleted();

  /// Records that onboarding finished. Safe to call repeatedly.
  Future<void> markCompleted();
}

/// Real store backed by `SharedPreferences` (device-local, non-sensitive).
class SharedPrefsOnboardingStore implements OnboardingStore {
  /// Preference key. Namespaced so it cannot collide with BYOK or auth data.
  static const String key = 'railmate.onboarding.completed.v1';

  final SharedPreferences _prefs;

  SharedPrefsOnboardingStore(this._prefs);

  /// Loads the backing store and returns a ready [SharedPrefsOnboardingStore].
  static Future<SharedPrefsOnboardingStore> open() async {
    return SharedPrefsOnboardingStore(await SharedPreferences.getInstance());
  }

  @override
  Future<bool> isCompleted() async => _prefs.getBool(key) ?? false;

  @override
  Future<void> markCompleted() async {
    await _prefs.setBool(key, true);
  }
}

/// In-memory store for tests and for the isolated widget harness.
class InMemoryOnboardingStore implements OnboardingStore {
  bool _completed;

  InMemoryOnboardingStore({bool initiallyCompleted = false})
    : _completed = initiallyCompleted;

  @override
  Future<bool> isCompleted() async => _completed;

  @override
  Future<void> markCompleted() async => _completed = true;
}
