/// Canonical public links for Journey Board posts and profiles (P42).
///
/// One place builds every shareable URL so the app, the QR/CTA and the public
/// website can never drift apart. The site is plain GitHub Pages hosting; the
/// data still comes from hosted Supabase. Nothing here embeds a token, an
/// access key or a guessed domain — the base URL is a compile-time constant
/// that matches the deployed Pages project path.
library;

/// Deployed GitHub Pages base (project site, so the path is required).
const String publicSiteBaseUrl = 'https://sa-mahi12.github.io/RailMate-BD';

/// Android deep-link scheme for the installed app (matches the manifest).
const String appDeepLinkScheme = 'railmatebd';

/// Canonical browser URL for one post.
String postPermalink(String postId) =>
    '$publicSiteBaseUrl/post.html?id=${Uri.encodeQueryComponent(postId.trim())}';

/// Canonical browser URL for one public profile.
String profilePermalink(String userId) =>
    '$publicSiteBaseUrl/profile.html?id=${Uri.encodeQueryComponent(userId.trim())}';

/// Canonical feed URL.
String get feedPermalink => '$publicSiteBaseUrl/';

/// In-app deep link for one post (`railmatebd://post/<uuid>`).
String postDeepLink(String postId) =>
    '$appDeepLinkScheme://post/${postId.trim()}';

/// Share-sheet text: the post body (bounded) plus the canonical URL.
///
/// The body is trimmed and clipped so a 2000-character post never becomes an
/// unusable share payload; the URL always survives.
String postShareText({required String body, required String postId}) {
  final String text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  const int maxBody = 240;
  final String clipped = text.length <= maxBody
      ? text
      : '${text.substring(0, maxBody).trimRight()}…';
  final String url = postPermalink(postId);
  return clipped.isEmpty ? url : '$clipped\n\n$url';
}

/// Parses an incoming post link into its post id, or null.
///
/// Accepted shapes:
/// * `railmatebd://post/<uuid>` and `railmate://post/<uuid>` (custom scheme)
/// * `https://sa-mahi12.github.io/RailMate-BD/post.html?id=<uuid>`
/// * `https://sa-mahi12.github.io/RailMate-BD/#/post/<uuid>` (defensive)
///
/// Malformed ids are rejected here, so the app can show an honest
/// "link not recognised" state instead of opening a broken screen.
String? parsePostLink(Uri? uri) {
  if (uri == null) return null;
  final String scheme = uri.scheme.toLowerCase();
  if (scheme == 'railmatebd' || scheme == 'railmate') {
    if (uri.host.toLowerCase() != 'post') return null;
    final String id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return isUuid(id) ? id : null;
  }
  if (scheme == 'https' || scheme == 'http') {
    if (uri.host.toLowerCase() != 'sa-mahi12.github.io') return null;
    if (!uri.path.startsWith('/RailMate-BD/')) return null;
    if (uri.path.endsWith('/post.html')) {
      final String id = (uri.queryParameters['id'] ?? '').trim();
      return isUuid(id) ? id : null;
    }
  }
  return null;
}

/// Parses an incoming profile link into its user id, or null.
String? parseProfileLink(Uri? uri) {
  if (uri == null) return null;
  final String scheme = uri.scheme.toLowerCase();
  if (scheme == 'railmatebd' || scheme == 'railmate') {
    if (uri.host.toLowerCase() != 'profile') return null;
    final String id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return isUuid(id) ? id : null;
  }
  if (scheme == 'https' || scheme == 'http') {
    if (uri.host.toLowerCase() != 'sa-mahi12.github.io') return null;
    if (!uri.path.startsWith('/RailMate-BD/')) return null;
    if (uri.path.endsWith('/profile.html')) {
      final String id = (uri.queryParameters['id'] ?? '').trim();
      return isUuid(id) ? id : null;
    }
  }
  return null;
}

/// Strict lowercase-hex UUID check (the ids the database issues).
bool isUuid(String value) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value.trim());
