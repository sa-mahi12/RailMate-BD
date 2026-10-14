/// Sign-up confirmation deep-link handling (RailMate BD).
///
/// The confirmation email bounces through Supabase verification and lands in
/// the app as `railmatebd://auth/verify` carrying a PKCE `code` query
/// parameter (supabase_flutter negotiates the PKCE flow by default). The app
/// exchanges that code for a session via
/// `SupabaseClient.auth.exchangeCodeForSession`.
///
/// Pure Dart: no Flutter, no Supabase, no network. The Flutter/host side
/// (see `AppGate`) owns listening, exchanging the code, and navigation;
/// this file only answers "is this a signup-verify link, and what code does
/// it carry" so it stays hermetically unit-testable.
///
/// The typed 6-digit OTP path (`verifyEmailOtp`) is unaffected: it works
/// whenever the project email template includes `{{ .Token }}`. This link
/// path is the fallback that works with the default link-only template —
/// and, crucially, it lands in the app instead of on the project's default
/// localhost Site URL (which is what happens when sign-up is issued without
/// an `emailRedirectTo`).
library;

/// PKCE code extracted from a signup-verify link.
class SignupVerifyCode {
  /// Single-use code the app exchanges for a session.
  final String code;

  const SignupVerifyCode({required this.code});
}

/// True when [uri] is a RailMate BD signup-verify link: our custom scheme,
/// the auth host, and the verify path. The `code` itself is checked by
/// [parseSignupVerifyLink]; a link without one is still a verify link, just
/// not an exchangeable one.
bool isSignupVerifyLink(Uri uri) {
  if (uri.scheme != 'railmatebd') return false;
  if (uri.host != 'auth') return false;
  return uri.path == '/verify' || uri.path.startsWith('/verify/');
}

/// Extracts the PKCE code, or null when the link is not a verify link or
/// carries no code.
///
/// Never throws: a malformed link is a null, and the caller falls back to
/// the manual OTP screen — never a dead end, never a code.
SignupVerifyCode? parseSignupVerifyLink(Uri uri) {
  if (!isSignupVerifyLink(uri)) return null;
  try {
    // Supabase appends the PKCE grant as a query parameter (`?code=…`).
    // Some clients surface redirect params in the fragment instead, so the
    // fragment is accepted as a fallback with the query winning.
    final Map<String, String> params = _allParams(uri);
    final String? code = params['code'];
    if (code == null || code.isEmpty) return null;
    return SignupVerifyCode(code: code);
  } catch (_) {
    return null;
  }
}

/// Query parameters plus fragment parameters, merged with query winning.
Map<String, String> _allParams(Uri uri) {
  final Map<String, String> merged = <String, String>{};
  final String fragment = uri.fragment;
  if (fragment.isNotEmpty) {
    try {
      merged.addAll(Uri.splitQueryString(fragment));
    } catch (_) {
      // A non-query fragment carries no credentials; ignore it.
    }
  }
  merged.addAll(uri.queryParameters);
  return merged;
}
