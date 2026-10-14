import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/verify_screen.dart';

/// Fake client: signup leaves the address unconfirmed; a later
/// [refreshSession] reports it confirmed (as if the email link was tapped).
class _LinkFakeClient implements AuthClient {
  AuthUser? user;
  int resends = 0;
  final StreamController<AuthUser?> controller =
      StreamController<AuthUser?>.broadcast();

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    user = AuthUser(id: 'u1', email: email, emailConfirmed: false);
    return user;
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    user = AuthUser(id: 'u1', email: email, emailConfirmed: true);
    return user;
  }

  @override
  Future<void> signOut() async {
    user = null;
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => controller.stream;

  @override
  Future<AuthUser?> refreshSession() async {
    if (user != null) {
      user = AuthUser(id: user!.id, email: user!.email, emailConfirmed: true);
    }
    return user;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    resends++;
  }

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    user = AuthUser(id: 'u1', email: email, emailConfirmed: true);
    return user;
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}
}

Future<AuthState> _unconfirmedAuth() async {
  final AuthState auth = AuthState(
    repository: AuthRepository(client: _LinkFakeClient()),
  );
  await auth.signUp(
    email: 'link@example.com',
    password: 'password123',
    username: 'tester',
  );
  expect(auth.status, AuthStatus.needsVerification);
  return auth;
}

/// Pumps a launcher that pushes the verify screen, so the re-check
/// success path can pop back to a real previous route.
Future<void> _pumpLauncher(WidgetTester tester, AuthState auth) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    VerifyScreen(auth: auth, email: 'link@example.com'),
              ),
            ),
            child: const Text('open verify'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open verify'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('VerifyScreen link-first UI', () {
    testWidgets('shows link instructions and no code entry', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await _unconfirmedAuth();
      addTearDown(auth.dispose);

      await _pumpLauncher(tester, auth);

      expect(find.byType(VerifyScreen), findsOneWidget);
      expect(find.textContaining('confirmation link'), findsWidgets);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Verify'), findsNothing);
      expect(find.text("I've confirmed — re-check"), findsOneWidget);
      expect(find.textContaining('Resend in'), findsOneWidget);

      await tester.pumpWidget(Container());
    });

    testWidgets('resend after the throttle re-sends the email', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await _unconfirmedAuth();
      addTearDown(auth.dispose);

      await _pumpLauncher(tester, auth);

      await tester.pump(const Duration(seconds: 61));
      await tester.tap(find.text('Resend confirmation email'));
      await tester.pump();

      expect(
        find.text('Confirmation email re-sent to link@example.com.'),
        findsOneWidget,
      );

      await tester.pumpWidget(Container());
    });

    testWidgets('re-check after link confirmation pops back verified', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await _unconfirmedAuth();
      addTearDown(auth.dispose);

      await _pumpLauncher(tester, auth);

      await tester.tap(find.text("I've confirmed — re-check"));
      await tester.pump();
      await tester.pump();

      expect(auth.status, AuthStatus.authenticated);
      expect(find.byType(VerifyScreen), findsNothing);
      expect(find.text('open verify'), findsOneWidget);

      await tester.pumpWidget(Container());
    });
  });
}
