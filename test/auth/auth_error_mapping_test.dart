import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';

/// Throws configured raw backend text to prove the consumer gate maps it
/// to plain language before it reaches [AuthState.errorMessage].
class _RawThrowingClient implements AuthClient {
  Object? signOutError;
  Object? verifyError;
  Object? resetError;
  Object? updateError;
  Object? refreshError;

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async => throw UnimplementedError();

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> signOut() async {
    if (signOutError != null) throw signOutError!;
  }

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<AuthUser?> refreshSession() async {
    if (refreshError != null) throw refreshError!;
    return null;
  }

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
    return null;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    if (resetError != null) throw resetError!;
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    if (updateError != null) throw updateError!;
  }
}

AuthState _state(_RawThrowingClient client) {
  final AuthState auth = AuthState(repository: AuthRepository(client: client));
  addTearDown(auth.dispose);
  return auth;
}

void main() {
  group('AuthState consumer error mapping', () {
    test('sign-out failure hides raw backend text', () async {
      final _RawThrowingClient client = _RawThrowingClient()
        ..signOutError = Exception('AuthException: socket blew up (raw)');
      final AuthState auth = _state(client);
      await auth.signOut();
      expect(auth.status, AuthStatus.error);
      expect(auth.errorMessage, "Couldn't sign you out. Please try again.");
    });

    test('expired verify token maps to resend guidance', () async {
      final _RawThrowingClient client = _RawThrowingClient()
        ..verifyError = Exception('Token has expired or is invalid (raw)');
      final AuthState auth = _state(client);
      await auth.verifyCode(email: 'a@b.co', token: '123456');
      expect(auth.status, AuthStatus.error);
      expect(
        auth.errorMessage,
        'This link or code has expired. Resend it and try the newest one.',
      );
    });

    test('reset-email transport failure stays neutral', () async {
      final _RawThrowingClient client = _RawThrowingClient()
        ..resetError = Exception('SocketException: failed host lookup (raw)');
      final AuthState auth = _state(client);
      final bool ok = await auth.requestPasswordReset('a@b.co');
      expect(ok, isFalse);
      expect(
        auth.errorMessage,
        'Network error — check your connection and retry.',
      );
      expect(auth.errorMessage, isNot(contains('SocketException')));
    });

    test('password-update failure hides raw text, hints expiry', () async {
      final _RawThrowingClient client = _RawThrowingClient()
        ..updateError = Exception('PostgrestException 500 (raw)');
      final AuthState auth = _state(client);
      final bool ok = await auth.completePasswordReset(newPassword: 'newpass1');
      expect(ok, isFalse);
      expect(auth.errorMessage, isNot(contains('PostgrestException')));
      expect(auth.errorMessage, contains('expired'));
    });

    test('failed restore lands unauthenticated with no error text', () async {
      final _RawThrowingClient client = _RawThrowingClient()
        ..refreshError = Exception('AuthException: session missing (raw)');
      final AuthState auth = _state(client);
      await auth.restore();
      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.errorMessage, isEmpty);
    });
  });
}
