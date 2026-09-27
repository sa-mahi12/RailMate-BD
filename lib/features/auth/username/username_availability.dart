/// B02 — username availability checker with injectable query (RailMate BD).
///
/// Pure Dart (depends only on `username.dart`): no network, no Flutter, so
/// unit tests inject a fake [UsernameExistsQuery] and never touch Supabase.
/// The API is debounce-friendly: [check] is a single-shot call and the
/// caller (e.g. `UsernameField`) debounces keystrokes before invoking it.
library;

import 'username.dart';

/// Availability states returned by [UsernameAvailabilityChecker.check].
enum UsernameAvailability {
  /// No input yet.
  initial,

  /// Fails [validateUsername]; no server query is issued.
  invalid,

  /// A server query is in flight (set by the UI layer, not [check]).
  checking,

  /// Valid format and not present in `public.usernames`.
  available,

  /// Valid format but already present in `public.usernames`.
  taken,

  /// Query threw (network/permission); caller may retry.
  error,
}

/// Returns true when [normalizedUsername] is already claimed.
///
/// Production wiring (Supabase, composed outside this file):
/// ```dart
/// UsernameAvailabilityChecker(existsQuery: (String normalized) async {
///   final List<Map<String, dynamic>> rows = await client
///       .from('usernames')
///       .select('username')
///       .eq('username', normalized)
///       .limit(1);
///   return rows.isNotEmpty;
/// })
/// ```
/// Documented SQL equivalent (see migration `20260927055200`):
/// `select exists(select 1 from public.usernames where username = <normalized>)`.
typedef UsernameExistsQuery = Future<bool> Function(String normalizedUsername);

/// Checks one normalized username against an injected existence query.
class UsernameAvailabilityChecker {
  /// Query used to test existence; fake in tests, Supabase query in prod.
  final UsernameExistsQuery existsQuery;

  const UsernameAvailabilityChecker({required this.existsQuery});

  /// Returns [UsernameAvailability.invalid] without querying when the format
  /// is bad, otherwise [UsernameAvailability.taken]/[available], or
  /// [UsernameAvailability.error] when the query throws.
  Future<UsernameAvailability> check(String raw) async {
    final String normalized = normalizeUsername(raw);
    if (!isValidUsername(normalized)) return UsernameAvailability.invalid;
    try {
      final bool taken = await existsQuery(normalized);
      return taken
          ? UsernameAvailability.taken
          : UsernameAvailability.available;
    } catch (_) {
      return UsernameAvailability.error;
    }
  }
}
