import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/verify_screen.dart';

import 'email_otp_fakes.dart';

Future<AuthState> _auth(EmailOtpFakeClient client) async {
  final auth = AuthState(repository: AuthRepository(client: client));
  addTearDown(auth.dispose);
  await auth.signUp(email: 'otp@example.com', password: 'password123');
  return auth;
}

Future<void> _pump(WidgetTester tester, AuthState auth) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VerifyScreen(auth: auth, email: 'otp@example.com'),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
}

void main() {
  testWidgets('root OTP completion does not pop an intervening route', (
    tester,
  ) async {
    final client = EmailOtpFakeClient()..verification = Completer<AuthUser?>();
    final auth = await _auth(client);
    await _pump(tester, auth);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other route')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    client.verification!.complete(
      const AuthUser(
        id: 'otp-user',
        email: 'otp@example.com',
        emailConfirmed: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('other route'), findsOneWidget);
    expect(auth.isAuthenticated, isTrue);
  });

  testWidgets('numeric paste submits six digits to the account email', (
    tester,
  ) async {
    final client = EmailOtpFakeClient();
    final auth = await _auth(client);
    await _pump(tester, auth);
    expect(find.textContaining('otp@example.com'), findsWidgets);
    expect(find.textContaining('confirmation link'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(field.keyboardType, TextInputType.number);
    await tester.enterText(find.byType(TextField), '12a345678');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123456',
    );
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(client.submittedEmail, 'otp@example.com');
    expect(client.submittedToken, '123456');
    expect(auth.isAuthenticated, isTrue);
    expect(tester.takeException(), isNull); // root must not pop
  });

  testWidgets('empty and short codes never reach verification', (tester) async {
    final client = EmailOtpFakeClient();
    await _pump(tester, await _auth(client));
    for (final input in ['', '12345']) {
      await tester.enterText(find.byType(TextField), input);
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter the 6-digit code from your email.'),
        findsOneWidget,
      );
      expect(client.verifications, 0);
    }
  });

  testWidgets('duplicate verify is suppressed while the request is pending', (
    tester,
  ) async {
    final client = EmailOtpFakeClient()..verification = Completer<AuthUser?>();
    final auth = await _auth(client);
    await _pump(tester, auth);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.tap(find.text('Verify code'));
    await tester.pump();
    expect(client.verifications, 1);
    expect(auth.isBusy, isTrue);
    client.verification!.completeError(
      Exception('otp_expired (private payload)'),
    );
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.needsVerification);
    expect(auth.isBusy, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('expired code stays editable and a new code can succeed', (
    tester,
  ) async {
    final client = EmailOtpFakeClient()
      ..verifyError = Exception('otp_expired private payload');
    final auth = await _auth(client);
    await _pump(tester, auth);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.needsVerification);
    expect(find.textContaining('private payload'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123456',
    );
    client.verifyError = null;
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, isTrue);
  });

  testWidgets('resend cooldown restarts after one accepted request', (
    tester,
  ) async {
    final client = EmailOtpFakeClient()..resend = Completer<void>();
    final auth = await _auth(client);
    await _pump(tester, auth);
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(find.text('Resend code'), findsNothing);
    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend code'));
    await tester.tap(find.text('Resend code'));
    await tester.pump();
    expect(client.resends, 1);
    expect(auth.isBusy, isTrue);
    client.resend!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(auth.isBusy, isFalse);
    expect(auth.errorMessage, isEmpty);
  });

  testWidgets('failed resend hides raw errors and remains retryable', (
    tester,
  ) async {
    final client = EmailOtpFakeClient()
      ..resendError = Exception('provider private payload');
    final auth = await _auth(client);
    await _pump(tester, auth);
    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.needsVerification);
    expect(auth.errorMessage, isNot(contains('private payload')));
    expect(find.text('Resend code'), findsOneWidget);
    client.resendError = null;
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(client.resends, 2);
    expect(auth.errorMessage, isEmpty);
    expect(find.textContaining('Resend in'), findsOneWidget);
  });

  testWidgets('pushed verification returns without removing its launcher', (
    tester,
  ) async {
    final auth = await _auth(EmailOtpFakeClient());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) =>
                    VerifyScreen(auth: auth, email: 'otp@example.com'),
              ),
            ),
            child: const Text('open verify'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open verify'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyScreen), findsNothing);
    expect(find.text('open verify'), findsOneWidget);
    expect(auth.isAuthenticated, isTrue);
  });

  test(
    'no verified user cannot authenticate or discard pending registration',
    () async {
      final auth = await _auth(EmailOtpFakeClient()..returnNoUser = true);
      await auth.verifyCode(email: 'otp@example.com', token: '123456');
      expect(auth.status, AuthStatus.needsVerification);
      expect(auth.user!.email, 'otp@example.com');
      expect(auth.isAuthenticated, isFalse);
      expect(auth.errorMessage, isNotEmpty);
    },
  );

  test('repository rejects a six-character nonnumeric code', () async {
    final client = EmailOtpFakeClient();
    final repository = AuthRepository(client: client);
    expect(
      () =>
          repository.verifyEmailOtp(email: 'otp@example.com', token: 'abcdef'),
      throwsArgumentError,
    );
    expect(client.verifications, 0);
  });
}
