import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/app.dart';
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
  testWidgets('app boots to Home tab; each tab shows its screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(RailMateApp(dependencies: _testDeps()));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // Home tab root rendered
    await tester.tap(find.text('My Trips').last);
    await tester.pumpAndSettle();
    // Logged out: genuine sign-in gate (not a setup placeholder).
    expect(find.text('Sign in to continue'), findsOneWidget);
    await tester.tap(find.text('Board').last);
    await tester.pumpAndSettle();
    expect(find.text('Journey Board'), findsOneWidget);
    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();
    // GuideListScreen header renders without backend.
    expect(find.text('Guide'), findsWidgets);
  });

  testWidgets('unknown route shows error screen', (WidgetTester tester) async {
    await tester.pumpWidget(RailMateApp(dependencies: _testDeps()));
    await tester.pumpAndSettle();
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.pushNamed('/no-such-route-xyz');
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown route'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown route'), findsNothing); // popped clean
  });
}
