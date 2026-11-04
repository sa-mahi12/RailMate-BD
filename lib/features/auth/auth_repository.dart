/// A02 — Supabase Auth wrapper with an injectable client (RailMate BD).
///
/// [AuthRepository] exposes email sign-up / sign-in / sign-out, session
/// restore and an auth-state stream. It depends only on the [AuthClient]
/// interface so unit tests use fakes and never touch the network.
///
/// Rules: no custom JWT, no raw passwords stored anywhere — passwords are
/// passed straight to Supabase Auth and never retained in memory beyond the
/// call.
library;

import 'dart:async';

/// Client-side validation messages thrown as [ArgumentError] by
/// [AuthRepository]. The auth UI may show these **verbatim** (they are our own
/// copy, never backend text), so a broken rule reads as the rule that was
/// broken instead of a generic "Registration failed".
const String kEmailEmptyMessage = 'Email must not be empty.';

/// Thrown when the address has no `@`.
const String kEmailMissingAtMessage = 'Email must contain "@".';

/// Thrown when a sign-in is attempted with a blank password.
const String kPasswordEmptyMessage = 'Password must not be empty.';

/// Thrown when a new password is shorter than the 8-character floor.
const String kPasswordTooShortMessage =
    'Password must be at least 8 characters.';

/// Thrown when the emailed verification code is not six digits.
const String kVerificationCodeLengthMessage =
    'Verification code must be 6 digits.';

/// Every message above, for the UI's verbatim-display allow-list.
const Set<String> kClientValidationMessages = <String>{
  kEmailEmptyMessage,
  kEmailMissingAtMessage,
  kPasswordEmptyMessage,
  kPasswordTooShortMessage,
  kVerificationCodeLengthMessage,
};

/// Minimal signed-in user snapshot. Carries no tokens or passwords.
class AuthUser {
  /// Supabase user id (`auth.users.id`).
  final String id;

  /// Account email address.
  final String email;

  /// True once the user confirmed their email address.
  final bool emailConfirmed;

  /// Optional profile metadata captured at sign-up (never a secret).
  final String? fullName;

  /// Optional profile metadata captured at sign-up (never a secret).
  final String? phone;

  /// Optional profile metadata captured at sign-up (never a secret).
  final String? username;

  const AuthUser({
    required this.id,
    required this.email,
    required this.emailConfirmed,
    this.fullName,
    this.phone,
    this.username,
  });
}

/// Injectable Supabase Auth client interface.
///
/// Production implementation: [SupabaseAuthClient] (below, backed by
/// `supabase_flutter`). Tests: hand-written fakes. No implementation may
/// perform real network I/O except [SupabaseAuthClient] on explicit user
/// action (sign-up / sign-in / sign-out / resend / refresh).
abstract class AuthClient {
  /// Registers [email] + [password]; stores [fullName]/[phone]/[username]
  /// as Supabase user metadata (not as secrets).
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  });

  /// Signs in with email + password.
  Future<AuthUser?> signIn({required String email, required String password});

  /// Signs out the current session.
  Future<void> signOut();

  /// Currently cached user, or null when signed out. No network I/O.
  AuthUser? get currentUser;

  /// Emits the current user on every auth-state change (sign-in, sign-out,
  /// token refresh, email confirmation).
  Stream<AuthUser?> authStateChanges();

  /// Re-reads the session/user from the server (used by the verify screen
  /// to detect a completed email confirmation).
  Future<AuthUser?> refreshSession();

  /// Re-sends the sign-up confirmation email to [email].
  Future<void> resendConfirmation(String email);

  /// Confirms the email address with the 6-digit code from the confirmation
  /// email (requires email-OTP enabled on the Supabase project). Returns
  /// the confirmed user.
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  });

  /// Requests a password-reset email for [email].
  ///
  /// Always resolves successfully for a well-formed address regardless of
  /// whether the account exists (no account enumeration). Network failures
  /// surface as exceptions so the UI can report them honestly.
  Future<void> requestPasswordReset(String email);

  /// Completes a password reset using the recovery link/OTP.
  ///
  /// [newPassword] must satisfy the project password policy; the caller is
  /// responsible for surfacing [ArgumentError] as a validation message.
  Future<void> updatePassword({required String newPassword});
}

/// Repository wrapping Supabase Auth behind the injectable [AuthClient].
class AuthRepository {
  /// Backing auth client (real Supabase adapter or test fake).
  final AuthClient client;

  AuthRepository({required this.client});

  /// Registers a new account. Returns the user, or null when the project
  /// requires email confirmation before a session exists (caller should
  /// then route to the verify screen).
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) {
    _requireEmail(email);
    _requirePassword(password);
    return client.signUp(
      email: email.trim(),
      password: password,
      fullName: _nullIfBlank(fullName),
      phone: _nullIfBlank(phone),
      username: _nullIfBlank(username),
    );
  }

  /// Signs in with email + password.
  Future<AuthUser?> signIn({required String email, required String password}) {
    _requireEmail(email);
    if (password.isEmpty) {
      throw ArgumentError(kPasswordEmptyMessage);
    }
    return client.signIn(email: email.trim(), password: password);
  }

  /// Signs out and clears the local session.
  Future<void> signOut() => client.signOut();

  /// Cached signed-in user, or null. Synchronous, no network I/O.
  AuthUser? get currentUser => client.currentUser;

  /// Restores the persisted session on startup. Returns the cached user
  /// (null when no session was persisted).
  Future<AuthUser?> restoreSession() => client.refreshSession();

  /// Stream of auth-state changes for session-aware UI.
  Stream<AuthUser?> authStateChanges() => client.authStateChanges();

  /// Re-checks confirmation/session state (verify screen polling/refresh).
  Future<AuthUser?> refreshSession() => client.refreshSession();

  /// Re-sends the sign-up confirmation email.
  Future<void> resendConfirmation(String email) {
    _requireEmail(email);
    return client.resendConfirmation(email.trim());
  }

  /// Confirms the email address with the 6-digit code from the email.
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    _requireEmail(email);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(token.trim())) {
      throw ArgumentError(kVerificationCodeLengthMessage);
    }
    return client.verifyEmailOtp(email: email.trim(), token: token.trim());
  }

  /// Requests a password-reset email for [email] (no account enumeration).
  Future<void> requestPasswordReset(String email) {
    _requireEmail(email);
    return client.requestPasswordReset(email.trim().toLowerCase());
  }

  /// Completes a password reset with the recovery credential.
  Future<void> updatePassword({required String newPassword}) {
    _requirePassword(newPassword);
    return client.updatePassword(newPassword: newPassword);
  }

  static void _requireEmail(String email) {
    if (email.trim().isEmpty) {
      throw ArgumentError(kEmailEmptyMessage);
    }
    if (!email.trim().contains('@')) {
      throw ArgumentError(kEmailMissingAtMessage);
    }
  }

  static void _requirePassword(String password) {
    if (password.length < 8) {
      throw ArgumentError(kPasswordTooShortMessage);
    }
  }

  static String? _nullIfBlank(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }
}
