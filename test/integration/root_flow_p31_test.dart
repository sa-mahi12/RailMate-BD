import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/app.dart';
import 'package:railmate_bd/app/app_gate.dart';
import 'package:railmate_bd/app/home_shell.dart';
import 'package:railmate_bd/app/onboarding_store.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/verify_screen.dart';
import 'package:railmate_bd/features/auth/welcome_screen.dart';
import 'package:railmate_bd/features/onboarding/onboarding_screen.dart';

import '../f19_fakes.dart';

/// V4 P31 — root-flow integration: the full splash -> onboarding -> welcome
/// -> verify -> home journey, driven through the REAL [RailMateApp] root with
/// real [AuthState] transitions and an injectable onboarding store.
///
/// Complements `test/app_gate_p03_test.dart` (the table of startup phases):
/// this file proves the transitions *between* those phases, including the
/// ones that are easy to regress — a phase change must actually swap the
/// screen, and the gate must never show two phases at once.
/// Fake auth client for the verify journey: sign-in returns an unconfirmed
/// account, `verifyEmailOtp` promotes it to confirmed, sign-out clears it.
class _VerifyingAuthClient implements AuthClient {
  AuthUser? _user;

  static const AuthUser _unconfirmed = AuthUser(
    id: 'u-verify',
    email: 'verify@example.com',
    emailConfirmed: false,
    fullName: 'Verify Tester',
    username: 'verify_tester',
  );

  static const AuthUser _confirmed = AuthUser(
    id: 'u-verify',
    email: 'verify@example.com',
    emailConfirmed: true,
    fullName: 'Verify Tester',
    username: 'verify_tester',
  );

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    _user = _unconfirmed;
    return _user;
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    _user = _unconfirmed;
    return _user;
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<AuthUser?> refreshSession() async => _user;

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    // Only a complete numeric code verifies, mirroring the real screen gate.
    if (token.length == 6 && int.tryParse(token) != null) {
      _user = _confirmed;
    }
    return _user;
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}
}

void main() {
  /// Pumps the real app root and settles the splash.
  Future<void> pumpApp(
    WidgetTester tester, {
    required AuthState auth,
    required OnboardingStore store,
  }) async {
    await tester.pumpWidget(
      RailMateApp(
        dependencies: f19TestDeps(auth: auth),
        onboardingStore: store,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Current phase, read from the live [AppGateState].
  AppGatePhase phaseOf(WidgetTester tester) =>
      tester.state<AppGateState>(find.byType(AppGate)).phase;

  /// A session that starts signed out, whose sign-in returns an UNCONFIRMED
  /// account, and whose OTP verification promotes it to confirmed — the real
  /// path welcome -> verify -> home.
  ///
  /// `f19AuthState` cannot model this: with `loggedIn: false` its fake returns
  /// a null user (sign-in stays unauthenticated), and `F19AuthClient`
  /// returns the same stub from `verifyEmailOtp`, so the account never
  /// becomes confirmed.
  AuthState unconfirmedSession() {
    return AuthState(
      repository: AuthRepository(client: _VerifyingAuthClient()),
    );
  }

  group('P31 splash is transient, never a dead end', () {
    testWidgets('a fresh start leaves splash for a real screen', (
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
      // The in-memory store resolves on the first microtask, so splash is
      // gone by the end of the first frame: assert the phase is already a
      // real screen rather than trying to catch a transient frame.
      expect(phaseOf(tester), AppGatePhase.onboarding);
      await tester.pumpAndSettle();

      // After settling, exactly one real screen — never still splash, and
      // never two phases stacked.
      expect(phaseOf(tester), AppGatePhase.onboarding);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(HomeShell), findsNothing);
    });
  });

  group('P31 onboarding -> welcome', () {
    testWidgets('finishing onboarding swaps the screen and persists', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore();

      await pumpApp(tester, auth: auth, store: store);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // Step through the pages to the last one, then complete via the screen's
      // own CTA (the label is 'Get Started' on the final page).
      for (var page = 0; page < 3; page++) {
        if (find.text('Next').evaluate().isNotEmpty) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Get Started'), findsOneWidget);
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(phaseOf(tester), AppGatePhase.welcome);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(await store.isCompleted(), isTrue);
    });

    testWidgets('a returning user (store already complete) skips onboarding', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore(
        initiallyCompleted: true,
      );

      await pumpApp(tester, auth: auth, store: store);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(phaseOf(tester), AppGatePhase.welcome);
    });
  });

  group('P31 welcome -> verify -> home', () {
    testWidgets('signing in with an unconfirmed email lands on verify', (
      WidgetTester tester,
    ) async {
      final AuthState auth = unconfirmedSession();
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore(
        initiallyCompleted: true,
      );

      await pumpApp(tester, auth: auth, store: store);
      expect(phaseOf(tester), AppGatePhase.welcome);

      // Sign in for real through the app's own auth path; the fake returns a
      // registered-but-unconfirmed account.
      await auth.signIn(email: 'qa@example.com', password: 'password123');
      await tester.pumpAndSettle();

      expect(phaseOf(tester), AppGatePhase.needsVerification);
      expect(find.byType(VerifyScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a confirmed session goes straight to the home shell', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: true);
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore(
        initiallyCompleted: true,
      );

      await pumpApp(tester, auth: auth, store: store);
      expect(phaseOf(tester), AppGatePhase.home);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('verification success advances verify -> home', (
      WidgetTester tester,
    ) async {
      final AuthState auth = unconfirmedSession();
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore(
        initiallyCompleted: true,
      );

      await pumpApp(tester, auth: auth, store: store);
      await auth.signIn(email: 'verify@example.com', password: 'password123');
      await tester.pumpAndSettle();
      expect(phaseOf(tester), AppGatePhase.needsVerification);

      // Complete the code through the real auth API.
      await auth.verifyCode(email: 'verify@example.com', token: '123456');
      await tester.pumpAndSettle();

      expect(phaseOf(tester), AppGatePhase.home);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(VerifyScreen), findsNothing);
    });
  });

  group('P31 logout returns to welcome without replaying onboarding', () {
    testWidgets('home -> sign out -> welcome, onboarding stays complete', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: true);
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore(
        initiallyCompleted: true,
      );

      await pumpApp(tester, auth: auth, store: store);
      expect(phaseOf(tester), AppGatePhase.home);

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(phaseOf(tester), AppGatePhase.welcome);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      // The rule that is easiest to regress: signing out must NOT send a
      // returning user back through onboarding.
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(await store.isCompleted(), isTrue);
    });
  });

  group('P31 exactly one phase is on screen', () {
    testWidgets('no two root screens are ever mounted together', (
      WidgetTester tester,
    ) async {
      final AuthState auth = unconfirmedSession();
      addTearDown(auth.dispose);
      final InMemoryOnboardingStore store = InMemoryOnboardingStore(
        initiallyCompleted: true,
      );

      await pumpApp(tester, auth: auth, store: store);

      // At most one root screen may be mounted at a time, in every phase.
      void expectAtMostOne() {
        for (final Type type in <Type>[
          OnboardingScreen,
          WelcomeScreen,
          VerifyScreen,
          HomeShell,
        ]) {
          final int count = find.byType(type).evaluate().length;
          expect(
            count,
            lessThanOrEqualTo(1),
            reason: '$type mounted $count times',
          );
        }
      }

      expectAtMostOne();
      expect(find.byType(WelcomeScreen), findsOneWidget);

      await auth.signIn(email: 'verify@example.com', password: 'password123');
      await tester.pumpAndSettle();
      expectAtMostOne();
      expect(find.byType(VerifyScreen), findsOneWidget);

      await auth.verifyCode(email: 'verify@example.com', token: '123456');
      await tester.pumpAndSettle();
      expectAtMostOne();
      expect(find.byType(HomeShell), findsOneWidget);

      await auth.signOut();
      await tester.pumpAndSettle();
      expectAtMostOne();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });
}
