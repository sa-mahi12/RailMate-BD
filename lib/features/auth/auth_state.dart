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
  bool _verificationBusy = false;
  int _authGeneration = 0;
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
  bool get isBusy => _status == AuthStatus.authenticating || _verificationBusy;

  /// Restores the persisted session on startup and subscribes to
  /// auth-state changes. Safe to call once from app bootstrap.
  ///
  /// A failed restore (no stored session, expired token, offline boot)
  /// lands on [AuthStatus.unauthenticated] WITHOUT an error message: the
  /// gate routes signed-out users correctly, and raw backend text must
  /// never pollute [errorMessage].
  Future<void> restore() async {
    _supersedeVerification();
    _setStatus(AuthStatus.authenticating);
    try {
      final AuthUser? restored = await repository.restoreSession();
      _applyUser(restored);
    } catch (_) {
      _user = null;
      _errorMessage = '';
      _setStatus(AuthStatus.unauthenticated);
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
    _supersedeVerification();
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
      _fail(_publicAuthError(e, fallback: 'Registration failed.'));
    }
  }

  /// Signs in with email + password.
  Future<void> signIn({required String email, required String password}) async {
    _supersedeVerification();
    _setStatus(AuthStatus.authenticating);
    try {
      final AuthUser? signedIn = await repository.signIn(
        email: email,
        password: password,
      );
      _applyUser(signedIn);
    } catch (e) {
      _fail(_publicAuthError(e, fallback: 'Login failed.'));
    }
  }

  /// Signs out and clears local session state.
  Future<void> signOut() async {
    _supersedeVerification();
    _setStatus(AuthStatus.authenticating);
    try {
      await repository.signOut();
      _user = null;
      _errorMessage = '';
      _setStatus(AuthStatus.unauthenticated);
    } catch (e) {
      _fail(_publicAuthError(e, fallback: "Couldn't sign you out."));
    }
  }

  /// Re-checks session/confirmation state (used by the verify screen after
  /// the user confirms their email, and by retry flows).
  Future<void> refreshVerification() async {
    try {
      final AuthUser? refreshed = await repository.refreshSession();
      _applyUser(refreshed);
    } catch (e) {
      _verificationFailed(
        _publicAuthError(e, fallback: 'Verification check failed.'),
        pending: _status == AuthStatus.needsVerification,
      );
    }
  }

  /// Re-sends the signup code without dislodging a pending verification route.
  Future<void> resendConfirmation(String email) async {
    if (isBusy) return;
    final int generation = _authGeneration;
    final bool pending = _status == AuthStatus.needsVerification;
    _verificationBusy = true;
    _errorMessage = '';
    notifyListeners();
    try {
      await repository.resendConfirmation(email);
    } catch (e) {
      if (generation != _authGeneration) return;
      _verificationFailed(
        _publicAuthError(e, fallback: 'Could not resend the code.'),
        pending: pending,
      );
    } finally {
      if (generation == _authGeneration) {
        _verificationBusy = false;
        notifyListeners();
      }
    }
  }

  /// Submits the 6-digit email confirmation code. On success the status
  /// becomes [AuthStatus.authenticated]. A pending registration remains on
  /// [AuthStatus.needsVerification] during requests and after safe errors.
  Future<void> verifyCode({
    required String email,
    required String token,
  }) async {
    if (isBusy) return;
    final int generation = _authGeneration;
    final bool pending = _status == AuthStatus.needsVerification;
    _verificationBusy = true;
    _errorMessage = '';
    if (pending) {
      notifyListeners();
    } else {
      _setStatus(AuthStatus.authenticating);
    }
    try {
      final AuthUser? confirmed = await repository.verifyEmailOtp(
        email: email,
        token: token,
      );
      if (generation != _authGeneration) return;
      if (confirmed == null || !confirmed.emailConfirmed) {
        _verificationFailed(
          'Email is not verified yet. Resend the code and try again.',
          pending: pending,
        );
      } else {
        _applyUser(confirmed);
      }
    } catch (e) {
      if (generation != _authGeneration) return;
      _verificationFailed(
        _publicAuthError(
          e,
          fallback: 'Could not verify the code. Check it or request a new one.',
        ),
        pending: pending,
      );
    } finally {
      if (generation == _authGeneration) {
        _verificationBusy = false;
        notifyListeners();
      }
    }
  }

  void _verificationFailed(String message, {required bool pending}) {
    // A concurrent confirmed session must not be downgraded by a late failure.
    if (isAuthenticated) return;
    _errorMessage = message;
    _setStatus(pending ? AuthStatus.needsVerification : AuthStatus.error);
  }

  /// Requests a password-reset email. Always reports neutral success so the
  /// UI cannot be used to discover which addresses have accounts; only a
  /// genuine transport/project failure sets [AuthStatus.error].
  Future<bool> requestPasswordReset(String email) async {
    _supersedeVerification();
    _setStatus(AuthStatus.authenticating);
    try {
      await repository.requestPasswordReset(email);
      _errorMessage = '';
      _setStatus(AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      // Neutral wording: never reveal whether the address has an account.
      _fail(_publicAuthError(e, fallback: 'Could not send the reset email.'));
      return false;
    }
  }

  /// Completes a password reset with the recovery credential.
  ///
  /// Returns true on success. On success the user is signed in (Supabase
  /// establishes a recovery session), so the gate advances to Home.
  Future<bool> completePasswordReset({required String newPassword}) async {
    _supersedeVerification();
    _setStatus(AuthStatus.authenticating);
    try {
      await repository.updatePassword(newPassword: newPassword);
      final AuthUser? refreshed = await repository.refreshSession();
      _applyUser(refreshed);
      return true;
    } catch (e) {
      _fail(
        _publicAuthError(
          e,
          fallback:
              "Couldn't update the password. The link may have expired — "
              'request a new one.',
        ),
      );
      return false;
    }
  }

  void _applyUser(AuthUser? next) {
    _supersedeVerification();
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

  /// New auth events/actions own the state; old OTP completions cannot undo them.
  void _supersedeVerification() {
    _authGeneration++;
    _verificationBusy = false;
  }

  /// Maps a raw auth failure to plain language for the UI.
  ///
  /// Consumer gate: backend exception text (class names, JSON bodies,
  /// status codes) is never shown to passengers. Known shapes get a
  /// specific, actionable sentence; everything else falls back to a
  /// generic retry message — both without the raw `$e` text.
  String _publicAuthError(Object e, {required String fallback}) {
    final String text = e.toString();
    // Client-side validation copy is safe to show verbatim (it is our own
    // sentence). The allow-list keeps an SDK ArgumentError - which can carry
    // backend detail - behind the same gate as everything else.
    if (e is ArgumentError) {
      final Object? message = e.message;
      if (message is String && kClientValidationMessages.contains(message)) {
        return message;
      }
    }
    if (text.contains('Invalid login credentials') ||
        text.contains('invalid_credentials')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (text.contains('already been registered') ||
        text.contains('already registered') ||
        text.contains('User already registered')) {
      return 'An account with this email already exists. '
          'Try logging in instead.';
    }
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('TimeoutException') ||
        text.contains('Network is unreachable') ||
        text.contains('Failed host lookup')) {
      return 'Network error — check your connection and retry.';
    }
    if (text.contains('expired') || text.contains('invalid token')) {
      return 'This link or code has expired. '
          'Resend it and try the newest one.';
    }
    if (text.contains('unexpected_failure') ||
        text.contains('Database error') ||
        text.contains('statusCode: 500')) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
    return '$fallback Please try again.';
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
