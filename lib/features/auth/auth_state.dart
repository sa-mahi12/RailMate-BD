/// A02 — minimal auth session state + route guard (RailMate BD).
///
/// [AuthState] is a [ChangeNotifier] holding the session lifecycle:
/// [AuthStatus.unauthenticated] → [AuthStatus.authenticating] →
/// [AuthStatus.authenticated], with [AuthStatus.needsVerification] while the
/// account's email is unconfirmed and [AuthStatus.error] carrying
/// [errorMessage] (safe to display — never contains secrets).
///
/// Call [restore] once on startup to rehydrate the persisted Supabase
/// session. Use [isAuthenticated] in route guards to protect
/// account-scoped routes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Session lifecycle visible to auth UI and route guards.
enum AuthStatus {
  /// No session (signed out, or startup restore found none).
  unauthenticated,

  /// An async auth operation is in progress.
  authenticating,

  /// Signed in with a confirmed email.
  authenticated,

  /// Signed in (or just registered) but email is not confirmed yet.
  needsVerification,

  /// Last operation failed; see [AuthState.errorMessage].
  error,
}

/// Minimal session state for the auth slice.
class AuthState extends ChangeNotifier {
  /// Backing repository (real Supabase adapter or test fake).
  final AuthRepository repository;

  AuthState({required this.repository});

  AuthStatus _status = AuthStatus.unauthenticated;
  AuthUser? _user;
  String _errorMessage = '';
  StreamSubscription<AuthUser?>? _subscription;

  /// Current lifecycle status.
  AuthStatus get status => _status;

  /// Signed-in user, or null.
  AuthUser? get user => _user;

  /// Last failure reason, or empty. Never contains secrets.
  String get errorMessage => _errorMessage;

  /// Route-guard helper: true only when a confirmed session exists.
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _user != null;

  /// True while an async auth operation is running.
  bool get isBusy => _status == AuthStatus.authenticating;

  /// Restores the persisted session on startup and subscribes to
  /// auth-state changes. Safe to call once from app bootstrap.
  Future<void> restore() async {
    _setStatus(AuthStatus.authenticating);
    try {
      final AuthUser? restored = await repository.restoreSession();
      _applyUser(restored);
    } catch (e) {
      _fail('Could not restore session: $e');
    }
    _subscription ??= repository.authStateChanges().listen(_applyUser);
  }

  /// Registers a new account. Routes to [AuthStatus.needsVerification] when
  /// the project requires email confirmation before a session exists.
  Future<void> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    _setStatus(AuthStatus.authenticating);
    try {
      final AuthUser? created = await repository.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
        username: username,
      );
      _applyUser(created);
    } catch (e) {
      _fail('Registration failed: $e');
    }
  }

  /// Signs in with email + password.
  Future<void> signIn({required String email, required String password}) async {
    _setStatus(AuthStatus.authenticating);
    try {
      final AuthUser? signedIn = await repository.signIn(
        email: email,
        password: password,
      );
      _applyUser(signedIn);
    } catch (e) {
      _fail('Login failed: $e');
    }
  }

  /// Signs out and clears local session state.
  Future<void> signOut() async {
    _setStatus(AuthStatus.authenticating);
    try {
      await repository.signOut();
      _user = null;
      _errorMessage = '';
      _setStatus(AuthStatus.unauthenticated);
    } catch (e) {
      _fail('Logout failed: $e');
    }
  }

  /// Re-checks session/confirmation state (used by the verify screen after
  /// the user confirms their email, and by retry flows).
  Future<void> refreshVerification() async {
    try {
      final AuthUser? refreshed = await repository.refreshSession();
      _applyUser(refreshed);
    } catch (e) {
      _fail('Verification check failed: $e');
    }
  }

  /// Re-sends the confirmation email. Keeps the current status; surfaces
  /// failures via [AuthStatus.error].
  Future<void> resendConfirmation(String email) async {
    try {
      await repository.resendConfirmation(email);
    } catch (e) {
      _fail('Could not resend confirmation email: $e');
    }
  }

  /// Submits the 6-digit email confirmation code. On success the status
  /// becomes [AuthStatus.authenticated]; on failure [AuthStatus.error]
  /// carries the reason.
  Future<void> verifyCode({
    required String email,
    required String token,
  }) async {
    _setStatus(AuthStatus.authenticating);
    try {
      final AuthUser? confirmed = await repository.verifyEmailOtp(
        email: email,
        token: token,
      );
      _applyUser(confirmed);
      if (confirmed == null) {
        _fail('Verification returned no session. Try resending the code.');
      }
    } catch (e) {
      _fail('Verification failed: $e');
    }
  }

  void _applyUser(AuthUser? next) {
    _user = next;
    _errorMessage = '';
    if (next == null) {
      _setStatus(AuthStatus.unauthenticated);
    } else if (next.emailConfirmed) {
      _setStatus(AuthStatus.authenticated);
    } else {
      _setStatus(AuthStatus.needsVerification);
    }
  }

  void _fail(String message) {
    _errorMessage = message;
    _setStatus(AuthStatus.error);
  }

  void _setStatus(AuthStatus next) {
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unsubFromAuth();
    super.dispose();
  }

  /// Cancels the auth-state subscription. Split from [dispose] so tests can
  /// drive the lifecycle without a widget tree.
  void unsubFromAuth() {
    _subscription?.cancel();
    _subscription = null;
  }
}
