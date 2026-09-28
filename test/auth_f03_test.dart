/// F03 — auth flow tests: login error path + register/verify lifecycle.
///
/// Hermetic: hand-written [AuthClient] fakes only, no network I/O.
/// Run with: `flutter test test/auth_f03_test.dart test/profile_f03_test.dart`
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/login_screen.dart';

import 'auth_repository_test.dart' show FakeAuthClient;

/// Fake whose sign-in always fails with a display-safe backend-style error.
class _FailingSignInClient implements AuthClient {
  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    return null;
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    throw Exception('Invalid login credentials');
  }

  @override
  Future<void> signOut() async {}

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<AuthUser?> refreshSession() async => null;

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    return null;
  }
}

void main() {
  testWidgets('login error path shows the failure message', (
    WidgetTester tester,
  ) async {
    final AuthState auth = AuthState(
      repository: AuthRepository(client: _FailingSignInClient()),
    );
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.enterText(find.byType(TextField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(auth.status, AuthStatus.error);
    expect(find.textContaining('Invalid login credentials'), findsOneWidget);
  });

  test(
    'register needsVerification, resend keeps it, verify authenticates',
    () async {
      final AuthState auth = AuthState(
        repository: AuthRepository(client: FakeAuthClient()),
      );
      addTearDown(() {
        auth.unsubFromAuth();
        auth.dispose();
      });

      await auth.signUp(
        email: 'a@b.co',
        password: 'password123',
        username: 'tester',
      );
      expect(auth.status, AuthStatus.needsVerification);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user?.username, 'tester');

      await auth.resendConfirmation('a@b.co');
      expect(auth.status, AuthStatus.needsVerification);

      await auth.verifyCode(email: 'a@b.co', token: '123456');
      expect(auth.status, AuthStatus.authenticated);
      expect(auth.isAuthenticated, isTrue);
    },
  );
}
