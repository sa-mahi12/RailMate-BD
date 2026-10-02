/// F03 — profile screen tests: account rendering, sign-out, key-setup link.
///
/// Hermetic: hand-written [AuthClient] fake only, no network I/O.
/// Run with: `flutter test test/auth_f03_test.dart test/profile_f03_test.dart`
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/routes.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/profile/profile_screen.dart';

/// Fake yielding a confirmed user with full profile metadata.
class _ProfileFakeClient implements AuthClient {
  AuthUser? user;
  bool signedOut = false;

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    user = AuthUser(
      id: 'u-profile',
      email: email,
      emailConfirmed: false,
      fullName: fullName,
      phone: phone,
      username: username,
    );
    return user;
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    user = const AuthUser(
      id: 'u-profile',
      email: 'a@b.co',
      emailConfirmed: true,
      fullName: 'Test User',
      username: 'tester',
    );
    return user;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    user = null;
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<AuthUser?> refreshSession() async => user;

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    return user;
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}
}

Future<AuthState> _signedIn(_ProfileFakeClient fake) async {
  final AuthState auth = AuthState(repository: AuthRepository(client: fake));
  await auth.signIn(email: 'a@b.co', password: 'password123');
  return auth;
}

void main() {
  testWidgets('profile renders signed-in account fields', (
    WidgetTester tester,
  ) async {
    final _ProfileFakeClient fake = _ProfileFakeClient();
    final AuthState auth = await _signedIn(fake);
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(auth: auth)));
    await tester.pumpAndSettle();

    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('a@b.co'), findsOneWidget);
    expect(find.text('@tester'), findsOneWidget);
    expect(find.text('u-profile'), findsOneWidget);
    expect(find.text('Email verified'), findsOneWidget);
  });

  testWidgets('sign-out calls through and shows signed-out view', (
    WidgetTester tester,
  ) async {
    final _ProfileFakeClient fake = _ProfileFakeClient();
    final AuthState auth = await _signedIn(fake);
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: ProfileScreen(auth: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(fake.signedOut, isTrue);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.user, isNull);
    expect(find.textContaining('Not signed in'), findsOneWidget);
  });

  testWidgets('AI key setup link navigates to AppRoutes.keySetup', (
    WidgetTester tester,
  ) async {
    final _ProfileFakeClient fake = _ProfileFakeClient();
    final AuthState auth = await _signedIn(fake);
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(auth: auth),
        onGenerateRoute: (RouteSettings settings) {
          if (settings.name == AppRoutes.keySetup) {
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('key-setup-marker')),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI key setup'));
    await tester.pumpAndSettle();

    expect(find.text('key-setup-marker'), findsOneWidget);
  });
}
