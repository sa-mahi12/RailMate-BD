import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/login_screen.dart';
import 'package:railmate_bd/features/auth/register_screen.dart';

import '../f19_fakes.dart';

/// Models GoTrue's repeated sign-up answer: an obfuscated user with an empty
/// identity list and no email sent.
class _RepeatSignupClient extends F19AuthClient {
  _RepeatSignupClient({this.alreadyRegistered = true, this.resendError});

  final bool alreadyRegistered;
  final Object? resendError;

  int resends = 0;
  String? resentEmail;

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async => AuthUser(
    id: 'existing-user',
    email: email,
    emailConfirmed: false,
    alreadyRegistered: alreadyRegistered,
  );

  @override
  Future<void> resendConfirmation(String email) async {
    resends++;
    resentEmail = email;
    if (resendError != null) throw resendError!;
  }
}

AuthState _state(F19AuthClient client) =>
    AuthState(repository: AuthRepository(client: client));

void main() {
  group('repeated signup for an existing address', () {
    test('asks for a fresh code and routes to verification', () async {
      final _RepeatSignupClient client = _RepeatSignupClient();
      final AuthState auth = _state(client);

      await auth.signUp(email: 'existing@example.com', password: 'password123');

      expect(client.resends, 1);
      expect(client.resentEmail, 'existing@example.com');
      expect(auth.status, AuthStatus.needsVerification);
      expect(auth.errorMessage, isEmpty);
    });

    test('a verified address is told to log in instead', () async {
      final _RepeatSignupClient client = _RepeatSignupClient(
        resendError: Exception('User already confirmed'),
      );
      final AuthState auth = _state(client);

      await auth.signUp(email: 'existing@example.com', password: 'password123');

      expect(auth.status, AuthStatus.error);
      expect(
        auth.errorMessage,
        'That email is already registered. Try logging in instead.',
      );
      expect(auth.emailAlreadyConfirmed, isTrue);
    });

    test('an unverified address is not flagged as confirmed', () async {
      final _RepeatSignupClient client = _RepeatSignupClient();
      final AuthState auth = _state(client);

      await auth.signUp(email: 'existing@example.com', password: 'password123');

      expect(auth.emailAlreadyConfirmed, isFalse);
    });

    testWidgets('a verified address lands on login with the email filled in', (
      WidgetTester tester,
    ) async {
      final _RepeatSignupClient client = _RepeatSignupClient(
        resendError: Exception('User already confirmed'),
      );
      final AuthState auth = _state(client);
      addTearDown(() {
        auth.unsubFromAuth();
        auth.dispose();
      });

      await tester.pumpWidget(MaterialApp(home: RegisterScreen(auth: auth)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Tanvir Ahmed');
      await tester.enterText(find.byType(TextField).at(1), 'owner@example.com');
      await tester.enterText(find.byType(TextField).at(2), '01712345678');
      await tester.enterText(find.byType(TextField).at(3), 'tanvir_1');
      await tester.enterText(find.byType(TextField).at(4), 'password123');
      await tester.enterText(find.byType(TextField).at(5), 'password123');
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      // The address is carried over so the owner only types a password.
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(
        find.textContaining('already has a verified RailMate account'),
        findsOneWidget,
      );
      // No red dead-end error remains on the login screen.
      expect(
        find.text('That email is already registered. Try logging in instead.'),
        findsNothing,
      );
    });

    test('a brand-new account is not treated as a repeat', () async {
      final _RepeatSignupClient client = _RepeatSignupClient(
        alreadyRegistered: false,
      );
      final AuthState auth = _state(client);

      await auth.signUp(email: 'new@example.com', password: 'password123');

      expect(client.resends, 0);
      expect(auth.status, AuthStatus.needsVerification);
    });
  });
}
