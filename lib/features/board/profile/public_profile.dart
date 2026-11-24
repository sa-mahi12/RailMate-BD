/// Safe public author identity (P42).
///
/// Mirrors the `public.public_profile_cards` view: id, username, display name,
/// join date and post count ONLY. Email, phone, Telegram identity, auth
/// metadata and booking/passenger data are deliberately absent and must never
/// be added here — the base `public.profiles` table stays own-row-only.
library;

class PublicProfile {
  /// `profiles.id` (also the auth user id).
  final String id;

  /// Claimed unique username (lowercase), null when the account has none.
  final String? username;

  /// Chosen display name; may be empty.
  final String displayName;

  /// Account creation time (public).
  final DateTime? joinedAt;

  /// Number of posts by this account (public aggregate only).
  final int postCount;

  const PublicProfile({
    required this.id,
    this.username,
    this.displayName = '',
    this.joinedAt,
    this.postCount = 0,
  });

  factory PublicProfile.fromMap(Map<String, dynamic> map) => PublicProfile(
    id: (map['id'] ?? '') as String,
    username: (map['username'] as String?)?.trim().isEmpty ?? true
        ? null
        : (map['username'] as String).trim(),
    displayName: ((map['display_name'] ?? '') as String).trim(),
    joinedAt: map['joined_at'] == null
        ? null
        : DateTime.tryParse(map['joined_at'] as String),
    postCount: (map['post_count'] as num?)?.toInt() ?? 0,
  );

  /// `@username`, or null when the account has no public username.
  String? get handle => username == null ? null : '@$username';

  /// Name shown on a card: display name, else `@username`, else 'Traveller'.
  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (username != null) return '@$username';
    return 'Traveller';
  }

  /// One-line identity: `Display Name · @username` (no duplicate handle).
  String get identityLine {
    final String? tag = handle;
    if (displayName.isNotEmpty && tag != null) return '$displayName · $tag';
    return label;
  }

  /// Initials for the avatar bubble (never an external avatar service).
  ///
  /// Uses the first letter of the first two words that start with a letter, so
  /// `Sam Mahi` → `SM`, `P42 Amina (demo)` → `PA` and a punctuation-only name
  /// degrades to `?` instead of printing brackets.
  String get initials {
    final String source = displayName.isNotEmpty
        ? displayName
        : (username ?? '');
    final List<String> letters = <String>[];
    for (final String word in source.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final String first = word.substring(0, 1);
      if (!RegExp(r'[A-Za-z\u00c0-\u024f]').hasMatch(first)) continue;
      letters.add(first.toUpperCase());
      if (letters.length == 2) break;
    }
    return letters.isEmpty ? '?' : letters.join();
  }
}
