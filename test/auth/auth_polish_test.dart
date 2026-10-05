import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/login_screen.dart';
import 'package:railmate_bd/features/auth/register_screen.dart';
import 'package:railmate_bd/features/auth/username/username_availability.dart';
import 'package:railmate_bd/features/auth/welcome_screen.dart';

import '../auth_repository_test.dart' show FakeAuthClient;

/// V4 P05/P07/P08 widget pins: register confirm-mismatch + live-taken
/// gates, login forgot-password navigation, welcome hero rendering.
void main() {
  AuthState fakeAuth() {
    final auth = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });
    return auth;
  }

  /// Auth sheets are long single-child scroll views; a plain drag is more
  /// robust here than scrollUntilVisible (several scrollables exist and the
  /// helper's default scrollable resolution is ambiguous).
  Future<void> dragAndTap(WidgetTester tester, Finder target) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('P07 register gates', () {
    Future<void> fillValidForm(
      WidgetTester tester, {
      required String confirm,
    }) async {
      await tester.enterText(find.byType(TextField).at(0), 'Tanvir Ahmed');
      await tester.enterText(find.byType(TextField).at(1), 'a@b.co');
      await tester.enterText(find.byType(TextField).at(2), '01712345678');
      await tester.enterText(find.byType(TextField).at(3), 'tanvir_1');
      await tester.enterText(find.byType(TextField).at(4), 'password123');
      await tester.enterText(find.byType(TextField).at(5), confirm);
      await tester.pumpAndSettle();
    }

    testWidgets('mismatched confirm blocks with a message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: RegisterScreen(auth: fakeAuth())),
      );
      await tester.pumpAndSettle();
      // Confirm field exists alongside password.
      expect(find.text('Confirm Password'), findsOneWidget);
      await fillValidForm(tester, confirm: 'different123');
      await dragAndTap(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('live taken username blocks submit', (
      WidgetTester tester,
    ) async {
      final checker = UsernameAvailabilityChecker(
        existsQuery: (_) async => true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(auth: fakeAuth(), usernameChecker: checker),
        ),
      );
      await tester.pumpAndSettle();
      await fillValidForm(tester, confirm: 'password123');
      // Debounce (400 ms) + query round trip, then the taken verdict shows.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        find.text('That username is taken — try another.'),
        findsOneWidget,
      );
      await dragAndTap(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(find.text('That username is already taken.'), findsOneWidget);
    });
  });

  group('P05 login/welcome polish', () {
    testWidgets('forgot password opens the reset flow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: fakeAuth())));
      await tester.pumpAndSettle();
      await dragAndTap(tester, find.text('Forgot password?').first);
      expect(find.text('Send reset link'), findsOneWidget);
    });

    testWidgets('welcome renders hero and both actions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: WelcomeScreen(auth: fakeAuth())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to'), findsOneWidget);
      expect(find.text('RailMate BD'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
    });
  });
}
