/// B02 — pure username normalize + validate helpers (RailMate BD).
///
/// Zero dependencies: no Flutter, no Supabase, no I/O. Safe for plain
/// `dart test` unit tests. Server mirror: `usernames_username_valid_check`
/// in `supabase/migrations/20260927055200_username_unique.sql`.
library;

/// Normalizes raw input: trims surrounding whitespace, lowercases.
///
/// Non-ASCII letters are lowercased but NOT transliterated, so validation
/// still rejects them (server CHECK enforces ASCII-only).
String normalizeUsername(String raw) => raw.trim().toLowerCase();

/// Username rules: 3-20 chars, lowercase letters/digits/underscore,
/// must start with a letter.
final RegExp _usernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

/// Returns true when [normalized] (see [normalizeUsername]) is usable.
bool isValidUsername(String normalized) =>
    _usernamePattern.hasMatch(normalized);

/// Human-readable error for raw input, or null when the value is usable.
///
/// Null means "format OK" — the caller must still check server availability.
String? validateUsername(String? raw) {
  final String normalized = normalizeUsername(raw ?? '');
  if (normalized.isEmpty) return 'Choose a username.';
  if (normalized.length < 3 || normalized.length > 20) {
    return 'Use 3–20 characters.';
  }
  if (!isValidUsername(normalized)) {
    return 'Lowercase letters, digits or _; start with a letter.';
  }
  return null;
}
