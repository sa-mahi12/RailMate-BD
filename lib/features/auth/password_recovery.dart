/// Password-recovery deep-link handling (RailMate BD).
///
/// The reset email bounces through Supabase verification and lands in the
/// app as `railmatebd://auth/reset-password` with the recovery credentials
/// attached. Supabase puts them in the **fragment**
/// (`#access_token=…&refresh_token=…&type=recovery`); some clients surface
/// them as query parameters instead, so both are read.
///
/// Pure Dart: no Flutter, no Supabase, no network. The Flutter/host side
/// (see `AppGate`) owns listening, establishing the session, and
/// navigation; this file only answers "is this a recovery link, and what
/// credentials does it carry" so it stays hermetically unit-testable.
library;

/// Credentials extracted from a recovery link.
class RecoveryCredentials {
  /// Long-lived credential the app exchanges for a session.
  final String refreshToken;

  /// Short-lived credential (kept for completeness/debugging; the app
  /// establishes the session from the refresh token).
  final String accessToken;

  const RecoveryCredentials({
    required this.refreshToken,
    required this.accessToken,
  });
}

/// True when [uri] is a RailMate BD password-recovery link: our custom
/// scheme, the auth host, the reset-password path, and `type=recovery`
/// among the parameters (query or fragment).
bool isPasswordRecoveryLink(Uri uri) {
  if (uri.scheme != 'railmatebd') return false;
  if (uri.host != 'auth') return false;
  if (!uri.path.startsWith('/reset-password')) return false;
  return _allParams(uri)['type'] == 'recovery';
}

/// Extracts the recovery credentials, or null when they are absent or the
/// link is not a recovery link at all.
///
/// Never throws: a malformed link is a null, and the caller falls back to
/// the manual reset flow.
RecoveryCredentials? parseRecoveryLink(Uri uri) {
  if (!isPasswordRecoveryLink(uri)) return null;
  try {
    final Map<String, String> params = _allParams(uri);
    final String? refresh = params['refresh_token'];
    final String? access = params['access_token'];
    if (refresh == null ||
        refresh.isEmpty ||
        access == null ||
        access.isEmpty) {
      return null;
    }
    return RecoveryCredentials(refreshToken: refresh, accessToken: access);
  } catch (_) {
    return null;
  }
}

/// Query parameters plus fragment parameters, merged with query winning.
/// Supabase emits the tokens in the fragment; defensive clients may move
/// them to the query, so both are accepted.
Map<String, String> _allParams(Uri uri) {
  final Map<String, String> merged = <String, String>{};
  final String fragment = uri.fragment;
  if (fragment.isNotEmpty) {
    // A fragment is `name=value&…` without the leading `#` (Uri strips it).
    try {
      merged.addAll(Uri.splitQueryString(fragment));
    } catch (_) {
      // A non-query fragment carries no credentials; ignore it.
    }
  }
  merged.addAll(uri.queryParameters);
  return merged;
}
