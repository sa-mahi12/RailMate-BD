/// A02 — production Supabase Auth adapter + connect hook (RailMate BD).
///
/// This is the only auth-slice file that imports `supabase_flutter` (already
/// a project dependency, `supabase_flutter: ^2.17.2`). Everything else talks
/// to the [AuthClient] interface in `auth_repository.dart`, so unit tests
/// use fakes and perform no network I/O.
///
/// Rules: anon (publishable) key only — never a service-role key. No network
/// call happens here except on explicit user action routed through
/// [SupabaseAuthClient] or the [supabaseConnect] startup hook.
library;

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../core/config/app_config.dart';
import '../../core/supabase/supabase_client.dart' show SupabaseConnect;
import 'auth_repository.dart';

/// Maps a Supabase [User] to the slice-local [AuthUser] snapshot.
AuthUser _toAuthUser(User user) {
  final Map<String, dynamic> meta = user.userMetadata ?? <String, dynamic>{};
  return AuthUser(
    id: user.id,
    email: user.email ?? '',
    emailConfirmed: user.emailConfirmedAt != null,
    fullName: meta['full_name'] as String?,
    phone: (meta['phone'] as String?) ?? user.phone,
    username: meta['username'] as String?,
  );
}

/// Production [AuthClient] backed by `Supabase.instance.client.auth`.
class SupabaseAuthClient implements AuthClient {
  /// Supabase client. Defaults to the global instance initialized by
  /// [supabaseConnect]; injectable for tests that need a shaped client.
  final SupabaseClient supabase;

  SupabaseAuthClient({SupabaseClient? supabase})
    : supabase = supabase ?? Supabase.instance.client;

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    final AuthResponse response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: <String, dynamic>{
        if (fullName case final String name) 'full_name': name,
        if (phone case final String number) 'phone': number,
        if (username case final String handle) 'username': handle,
      },
    );
    final User? user = response.session?.user ?? response.user;
    return user == null ? null : _toAuthUser(user);
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final User? user = response.session?.user ?? response.user;
    return user == null ? null : _toAuthUser(user);
  }

  @override
  Future<void> signOut() => supabase.auth.signOut();

  @override
  AuthUser? get currentUser {
    final User? user = supabase.auth.currentUser;
    return user == null ? null : _toAuthUser(user);
  }

  @override
  Stream<AuthUser?> authStateChanges() => supabase.auth.onAuthStateChange.map(
    (AuthState state) =>
        state.session == null ? null : _toAuthUser(state.session!.user),
  );

  @override
  Future<AuthUser?> refreshSession() async {
    final AuthResponse response = await supabase.auth.refreshSession();
    final User? user = response.session?.user ?? supabase.auth.currentUser;
    return user == null ? null : _toAuthUser(user);
  }

  @override
  Future<void> resendConfirmation(String email) async {
    await supabase.auth.resend(type: OtpType.signup, email: email);
  }

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final AuthResponse response = await supabase.auth.verifyOTP(
      type: OtpType.signup,
      token: token,
      email: email,
    );
    final User? user = response.session?.user ?? response.user;
    return user == null ? null : _toAuthUser(user);
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    // No account enumeration: Supabase answers the same way for unknown
    // addresses, and the UI shows a neutral confirmation either way.
    await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: kPasswordResetRedirect,
    );
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }
}

/// Web redirect target baked into recovery emails.
///
/// The deep link lands on the app's universal link / custom scheme; Supabase
/// appends the recovery token, which the app forwards to
/// [AuthClient.updatePassword]. Kept as a constant so the value stays
/// consistent between the email template and the app.
const String kPasswordResetRedirect = 'railmatebd://auth/reset-password';

/// [SupabaseConnect] hook for [SupabaseBootstrap.initialize]: performs the
/// real `Supabase.initialize(url, anonKey)` call. Pass it at app startup:
///
/// ```dart
/// await SupabaseBootstrap.instance.initialize(connect: supabaseConnect);
/// ```
///
/// Uses only the publishable (anon) key from [AppConfig]; never service-role.
Future<void> supabaseConnect(AppConfig config) {
  return Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabaseAnonKey,
  );
}
