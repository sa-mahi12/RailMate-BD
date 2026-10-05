import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/profile/profile_screen.dart';

import '../auth_repository_test.dart' show FakeAuthClient;

/// V4 P23 widget pins: profile signed-out state and the About dialog's
/// demonstration-only contract.
void main() {
  AuthState state({required bool signedIn}) {
    final auth = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });
    return auth;
  }

  Future<AuthState> signedInState() async {
    final auth = state(signedIn: true);
    await auth.signIn(email: 'a@b.co', password: 'password123');
    return auth;
  }

  group('P23 profile polish', () {
    testWidgets('signed-out renders the honest empty state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(auth: state(signedIn: false))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Sign in to see your profile.'), findsOneWidget);
    });

    testWidgets('about dialog states the demonstration-only contract', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(auth: await signedInState())),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('About this app'));
      await tester.pumpAndSettle();
      expect(find.textContaining('DEMONSTRATION ONLY'), findsOneWidget);
    });
  });
}
