import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/app/home_shell.dart';
import 'package:railmate_bd/design/motion/pressable.dart';
import 'package:railmate_bd/design/motion/reduced_motion.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';

/// P09 — bottom-navigation selection motion, verified without a backend.
///
/// Same client-less composition as `navigation_i01_test.dart`: no Supabase
/// client, so the shell opens no realtime channel and every backend closure
/// fails honestly instead of returning fake rows.
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

Future<void> _pumpShell(WidgetTester tester, {bool reduced = false}) async {
  await tester.pumpWidget(
    MotionGate(
      overrideReduced: reduced ? true : null,
      child: MaterialApp(home: HomeShell(dependencies: _testDeps())),
    ),
  );
  await tester.pumpAndSettle();
}

AnimatedAlign _indicator(WidgetTester tester) =>
    tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));

/// The indicator's *current* (mid-flight) horizontal slot, resolved for LTR.
///
/// [AnimatedAlign.alignment] is only the tween target; the animating value
/// lives on the render object, which is what a visual check needs.
double _indicatorX(WidgetTester tester) => tester
    .renderObject<RenderPositionedBox>(find.byType(AnimatedAlign))
    .alignment
    .resolve(TextDirection.ltr)
    .x;

/// The active tab body's entrance opacity.
///
/// `IndexedStack` reports only the selected child as an on-stage child, so a
/// default finder sees exactly the visible tab's subtree.
double _bodyOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity)).opacity;

void main() {
  group('animated bottom navigation', () {
    testWidgets('keeps the four contract tabs with their labels', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);
      for (final String label in <String>[
        'Home',
        'Bookings',
        'Board',
        'Profile',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
        // Each tab is press-scaled (sibling screens may use PressScale too).
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(PressScale),
          ),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('starts on Home and switches on tap', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);
      expect(find.text('Journey Board'), findsNothing);

      await tester.tap(find.text('Board').last);
      await tester.pumpAndSettle();
      expect(find.text('Journey Board'), findsOneWidget);

      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Not signed in'), findsOneWidget);
    });

    testWidgets('the selection indicator tweens between slots', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);
      expect(_indicatorX(tester), -1.0);

      await tester.tap(find.text('Profile').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-flight: part way between the Home (-1) and Profile (1) slots.
      final double midX = _indicatorX(tester);
      expect(midX, greaterThan(-1.0));
      expect(midX, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_indicatorX(tester), 1.0);
    });

    testWidgets('the selected icon scales up and crossfades variants', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);
      AnimatedScale scale = tester.widget<AnimatedScale>(
        find
            .ancestor(
              of: find.byIcon(Icons.forum_outlined),
              matching: find.byType(AnimatedScale),
            )
            .first,
      );
      expect(scale.scale, 1.0);

      await tester.tap(find.text('Board').last);
      await tester.pumpAndSettle();
      // Selected Board tab uses the filled variant, scaled per the matrix.
      expect(find.byIcon(Icons.forum), findsOneWidget);
      scale = tester.widget<AnimatedScale>(
        find
            .ancestor(
              of: find.byIcon(Icons.forum),
              matching: find.byType(AnimatedScale),
            )
            .first,
      );
      expect(scale.scale, greaterThan(1.0));
    });

    testWidgets('reduced motion collapses the indicator and icon motion', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester, reduced: true);
      expect(_indicator(tester).duration, Duration.zero);

      await tester.tap(find.text('Board').last);
      await tester.pump();
      // Colour/position changes with no animated tween at all.
      expect(_indicator(tester).duration, Duration.zero);
      expect(_indicatorX(tester), closeTo(1.0 / 3.0, 1e-9));
      final AnimatedSwitcher swap = tester.widget<AnimatedSwitcher>(
        find
            .descendant(
              of: find.byType(PressScale),
              matching: find.byType(AnimatedSwitcher),
            )
            .at(2),
      );
      expect(swap.duration, Duration.zero);
      expect(find.text('Journey Board'), findsOneWidget);
    });

    testWidgets('tabs stay keyboard/screen-reader reachable', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpShell(tester);
      for (final String label in <String>[
        'Home',
        'Bookings',
        'Board',
        'Profile',
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      handle.dispose();
    });

    testWidgets('a tab body fades in the first time it is shown', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Board').last);
      await tester.pump();
      // The tab that just became visible starts hidden, then settles visible.
      expect(_bodyOpacity(tester), 0.0);

      // The first tick of a freshly started controller reports elapsed zero,
      // so the fade needs one warm-up frame before it is observably in flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final double midFlight = _bodyOpacity(tester);
      expect(midFlight, greaterThan(0.0));
      expect(midFlight, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_bodyOpacity(tester), 1.0);
    });

    testWidgets('the body fade is not replayed on a later visit', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);
      await tester.tap(find.text('Board').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Board').last);
      await tester.pumpAndSettle();

      // Re-visiting must not put the body back at zero opacity.
      expect(_bodyOpacity(tester), 1.0);
    });
  });
}
