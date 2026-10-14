import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/app_gate.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/app/link_source.dart';
import 'package:railmate_bd/app/onboarding_store.dart';
import 'package:railmate_bd/app/routes.dart';
import 'package:railmate_bd/features/auth/auth_callback_screen.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthState, AuthUser;

class _LoggedOutClient implements AuthClient {
  final StreamController<AuthUser?> controller =
      StreamController<AuthUser?>.broadcast();

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
  Stream<AuthUser?> authStateChanges() => controller.stream;

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

/// Controllable cold-start + warm link delivery without platform channels.
class _FakeLinks implements LinkSource {
  final Uri? initial;
  final StreamController<Uri> warm = StreamController<Uri>.broadcast();

  _FakeLinks({this.initial});

  @override
  Future<Uri?> getInitialLink() async => initial;

  @override
  Stream<Uri> get uriLinkStream => warm.stream;
}

AuthState _loggedOutAuth() {
  final AuthState auth = AuthState(
    repository: AuthRepository(client: _LoggedOutClient()),
  );
  addTearDown(auth.dispose);
  return auth;
}

AppDependencies _depsWithClient(AuthState auth) {
  // Offline dummy: never touched — the tests inject a fake exchanger.
  // Token auto-refresh is disabled so constructing the client starts no
  // periodic timers (which would fail teardown / hang the fake clock).
  final SupabaseClient client = SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return AppDependencies.test(
    auth: auth,
    searchApi: _ThrowingSearchApi(),
    client: client,
  );
}

Future<void> _pushAndSettle(
  WidgetTester tester,
  AppDependencies deps,
  String name,
) async {
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (RouteSettings settings) =>
          AppRoutes.onGenerateRoute(settings, dependencies: deps),
      home: const SizedBox.shrink(),
    ),
  );
  await tester.pump();
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(name);
  // Fixed pumps only: AuthCallbackScreen shows an indeterminate progress
  // indicator, so pumpAndSettle would never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('auth-callback routes never hit the error screen', () {
    const List<String> names = <String>[
      '/auth/verify',
      '/auth/verify?code=pkce-code-123',
      '/auth/reset-password',
      '/auth/reset-password?code=recovery-code-456',
    ];

    for (final String name in names) {
      testWidgets('route table resolves $name', (WidgetTester tester) async {
        final AppDependencies deps = _depsWithClient(_loggedOutAuth());
        await _pushAndSettle(tester, deps, name);
        expect(find.byType(AuthCallbackScreen), findsOneWidget);
        expect(find.byType(RouteErrorScreen), findsNothing);
        expect(find.text("We couldn't open this page"), findsNothing);
      });
    }

    testWidgets('unknown routes still hit the error screen', (
      WidgetTester tester,
    ) async {
      final AppDependencies deps = _depsWithClient(_loggedOutAuth());
      await _pushAndSettle(tester, deps, '/no-such-route-xyz');
      expect(find.byType(RouteErrorScreen), findsOneWidget);
    });

    testWidgets('callback kind matches the path', (WidgetTester tester) async {
      final AppDependencies deps = _depsWithClient(_loggedOutAuth());
      await _pushAndSettle(tester, deps, '/auth/reset-password');
      final AuthCallbackScreen screen = tester.widget(
        find.byType(AuthCallbackScreen),
      );
      expect(screen.kind, AuthCallbackKind.passwordReset);
      expect(find.text('Preparing password reset…'), findsOneWidget);
    });
  });

  group('AuthCallbackScreen', () {
    testWidgets('unauthenticated shows progress with a way back', (
      WidgetTester tester,
    ) async {
      final AuthState auth = _loggedOutAuth();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AuthCallbackScreen(
                      auth: auth,
                      kind: AuthCallbackKind.signupVerify,
                    ),
                  ),
                ),
                child: const Text('open callback'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open callback'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Completing sign-in…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      // The pop transition runs 300 ms; the spinner never settles, so
      // advance past the transition with fixed pumps instead.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AuthCallbackScreen), findsNothing);
    });
  });

  group('AppGate link ownership: cold start, warm, exactly-once', () {
    const String code = 'single-use-pkce-code';
    late _FakeLinks links;
    late List<String> exchanged;

    setUp(() {
      exchanged = <String>[];
      links = _FakeLinks(
        initial: Uri.parse('railmatebd://auth/verify?code=$code'),
      );
      addTearDown(links.warm.close);
    });

    Future<void> pumpGate(WidgetTester tester) async {
      final AuthState auth = _loggedOutAuth();
      await tester.pumpWidget(
        MaterialApp(
          home: AppGate(
            dependencies: _depsWithClient(auth),
            store: InMemoryOnboardingStore(initiallyCompleted: true),
            linkSource: links,
            codeExchanger: (SupabaseClient client, String c) async {
              exchanged.add(c);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('cold-start link is exchanged once', (
      WidgetTester tester,
    ) async {
      await pumpGate(tester);
      expect(exchanged, <String>[code]);
    });

    testWidgets('warm link is exchanged once', (WidgetTester tester) async {
      links = _FakeLinks();
      addTearDown(links.warm.close);
      await pumpGate(tester);
      expect(exchanged, isEmpty);

      links.warm.add(Uri.parse('railmatebd://auth/verify?code=$code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(exchanged, <String>[code]);
    });

    testWidgets('cold + warm delivery of the same code exchanges once', (
      WidgetTester tester,
    ) async {
      await pumpGate(tester);
      expect(exchanged, <String>[code]);

      // The warm stream re-delivers the same launch link afterwards.
      links.warm.add(Uri.parse('railmatebd://auth/verify?code=$code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(exchanged, <String>[code]);
    });
  });
}
