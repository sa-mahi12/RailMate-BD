/// P03 — root gate startup state machine tests (RailMate BD).
///
/// These pin the real startup contract:
///
/// | onboarding | session            | expected screen |
/// |------------|--------------------|-----------------|
/// | not done   | none               | onboarding      |
/// | done       | none               | welcome         |
/// | any        | authenticated      | home shell      |
/// | any        | unconfirmed email  | verify          |
///
/// plus the two rules that are easy to regress: onboarding completion is
/// independent of the session, and logout must not replay onboarding.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/app.dart';
import 'package:railmate_bd/app/app_gate.dart';
import 'package:railmate_bd/app/home_shell.dart';
import 'package:railmate_bd/app/onboarding_store.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/verify_screen.dart';
import 'package:railmate_bd/features/auth/welcome_screen.dart';
import 'package:railmate_bd/features/onboarding/onboarding_screen.dart';

import 'f19_fakes.dart';

void main() {
  testWidgets('first run: no session + onboarding incomplete -> onboarding', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: false);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        onboardingStore: InMemoryOnboardingStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('onboarding completion advances to Welcome and persists', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: false);
    addTearDown(auth.dispose);
    final InMemoryOnboardingStore store = InMemoryOnboardingStore();

    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        onboardingStore: store,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    // Skip finishes the tour (same exit as completing page 3).
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    // Completion is durable, not a per-session decision.
    expect(await store.isCompleted(), isTrue);
  });

  testWidgets('returning signed out: onboarding done -> welcome (no replay)', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: false);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        onboardingStore: InMemoryOnboardingStore(initiallyCompleted: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('restored authenticated session -> home shell', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: true);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        // Even with onboarding NOT completed, a real session wins: the gate
        // must not trap a signed-in user behind the tour.
        onboardingStore: InMemoryOnboardingStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('unconfirmed email -> verify screen, not home', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(
      loggedIn: true,
      emailConfirmed: false,
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        onboardingStore: InMemoryOnboardingStore(initiallyCompleted: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VerifyScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('logout returns to Welcome and does not replay onboarding', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: true);
    addTearDown(auth.dispose);
    final InMemoryOnboardingStore store = InMemoryOnboardingStore(
      initiallyCompleted: true,
    );

    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        onboardingStore: store,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('AppGate exposes a readable phase for QA/tests', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: false);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppGate(
          dependencies: f19TestDeps(auth: auth),
          store: InMemoryOnboardingStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final AppGateState gate = tester.state(find.byType(AppGate));
    expect(gate.phase, AppGatePhase.onboarding);
  });

  testWidgets('splash is the pre-resolve phase, never a dead end', (
    WidgetTester tester,
  ) async {
    final AuthState auth = await f19AuthState(loggedIn: true);
    addTearDown(auth.dispose);

    // Before the async store read completes the gate is in `splash`.
    await tester.pumpWidget(
      MaterialApp(
        home: AppGate(
          dependencies: f19TestDeps(auth: auth),
          store: _NeverStore(),
        ),
      ),
    );
    await tester.pump();

    final AppGateState gate = tester.state(find.byType(AppGate));
    expect(gate.phase, AppGatePhase.splash);
    expect(find.text('RailMate BD'), findsWidgets); // wordmark on splash
  });
}

/// Store whose read never completes, to observe the splash phase.
class _NeverStore implements OnboardingStore {
  @override
  Future<bool> isCompleted() => Completer<bool>().future;
  @override
  Future<void> markCompleted() async {}
}
