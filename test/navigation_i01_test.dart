import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/app.dart';
import 'package:railmate_bd/app/home_shell.dart';
import 'package:railmate_bd/app/onboarding_store.dart';
import 'package:railmate_bd/app/routes.dart';
import 'package:railmate_bd/features/auth/welcome_screen.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';

class _LoggedOutClient implements AuthClient {
  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) => throw UnimplementedError();

  @override
  Future<AuthUser?> signIn({required String email, required String password}) =>
      throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}
}

class _ThrowingSearchApi implements SearchApi {
  @override
  Future<List<Station>> fetchStations() =>
      throw const NetworkError('test: no backend');

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) => throw const NetworkError('test: no backend');
}

AppDependencies _testDeps() => AppDependencies.test(
  auth: AuthState(repository: AuthRepository(client: _LoggedOutClient())),
  searchApi: _ThrowingSearchApi(),
);

void main() {
  // P03: the root is no longer an unconditional HomeShell. A signed-out user
  // with completed onboarding lands on the auth Welcome screen, so the tab
  // assertions below drive HomeShell directly (its own tab contract is
  // unchanged).
  testWidgets('signed-out boot lands on Welcome, not the tab shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      RailMateApp(
        dependencies: _testDeps(),
        onboardingStore: InMemoryOnboardingStore(initiallyCompleted: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing); // no tab shell while signed out
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('HomeShell tabs each show their screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeShell(dependencies: _testDeps())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // Home tab root rendered
    await tester.tap(find.text('Bookings').last);
    await tester.pumpAndSettle();
    // Logged out: genuine sign-in gate (not a setup placeholder).
    expect(find.text('Sign in to continue'), findsOneWidget);
    await tester.tap(find.text('Board').last);
    await tester.pumpAndSettle();
    expect(find.text('Journey Board'), findsOneWidget);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    // ProfileScreen logged-out state renders without backend.
    expect(find.text('Not signed in'), findsOneWidget);
  });

  testWidgets('unknown route shows error screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: AppRoutes.onGenerateRoute,
        home: HomeShell(dependencies: _testDeps()),
      ),
    );
    await tester.pumpAndSettle();
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.pushNamed('/no-such-route-xyz');
    await tester.pumpAndSettle();
    // Consumer gate: no route name leaks; the page names the problem in
    // plain language and offers a way back.
    expect(find.text("We couldn't open this page"), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't open this page"),
      findsNothing,
    ); // popped clean
  });
}
