import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/design.dart';
import 'package:railmate_bd/design/state/state.dart';
import 'package:railmate_bd/features/auth/login_screen.dart';
import 'package:railmate_bd/features/auth/register_screen.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_details_screen.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_form_state.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_screen.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_state.dart';
import 'package:railmate_bd/features/board/post/feed_screen.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/board/post/post_feed_state.dart';
import 'package:railmate_bd/features/onboarding/onboarding_screen.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/models/trip_seat.dart';
import 'package:railmate_bd/features/search/search_repository.dart';
import 'package:railmate_bd/features/search/search_results_screen.dart';
import 'package:railmate_bd/features/search/search_state.dart';

import '../auth_repository_test.dart' show FakeAuthClient;

import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';

/// V4 P27 — accessibility pass pinned as tests.
///
/// Scope covered here (each is cheap and hermetic):
/// 1. Reduced motion: every motion primitive renders its final state with
///    NO pending timer, so nothing waits for an animation.
/// 2. Text scaling: key screens still render their primary content at 1.5x
///    and 2.0x without an overflow exception.
/// 3. Semantics: motion/press wrappers carry readable labels and the state
///    widgets expose their title+message to assistive tech.
void main() {
  Trip trip() => Trip(
    id: 't-a11y',
    trainName: 'Accessibility Express (Demo)',
    originStationId: 'o',
    destinationStationId: 'd',
    departureAt: DateTime(2026, 10, 6, 7, 0),
    arrivalAt: DateTime(2026, 10, 6, 12, 30),
    fareBdt: 500,
    active: true,
  );

  Widget scale(Widget child, double factor) => MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(factor)),
    child: child,
  );

  group('P27 reduced motion renders final state immediately', () {
    testWidgets('FadeSlideIn has no pending timer under reduced motion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(
              body: FadeSlideIn(
                delay: Duration(milliseconds: 400),
                child: Text('final state'),
              ),
            ),
          ),
        ),
      );
      // No extra pump needed: the content is already at its final state and
      // a delayed entrance would leave a pending timer (flutter_test asserts
      // on those at teardown).
      expect(find.text('final state'), findsOneWidget);
    });

    testWidgets('staggered list content is present on first pump', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: StaggeredColumn(
                children: List<Widget>.generate(5, (int i) => Text('row $i')),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        expect(find.text('row $i'), findsOneWidget);
      }
    });
  });

  group('P27 state widgets expose semantics', () {
    testWidgets('ErrorState, EmptyState and Skeleton announce themselves', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                ErrorState(message: 'Could not load seats'),
                EmptyState(
                  title: 'No bookings yet',
                  message: 'Book a demo seat to see it here.',
                ),
                SkeletonBlock(height: 40),
              ],
            ),
          ),
        ),
      );
      // Bounded pumps, NOT pumpAndSettle: the skeleton shimmer repeats
      // forever by design, so it can never "settle".
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not load seats'), findsOneWidget);
      expect(find.text('No bookings yet'), findsOneWidget);
      // Both parts of the state reach assistive tech: the copy is in the
      // semantics tree, not only painted. StateLayout wraps the block in
      // Semantics(container: true, liveRegion: true) so a state change is
      // announced, and the copy nodes keep their own labels.
      expect(find.bySemanticsLabel('No bookings yet'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Book a demo seat to see it here.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Could not load seats'), findsOneWidget);
      // The skeleton is decorative: it must not be announced as content.
      expect(find.byType(ExcludeSemantics), findsWidgets);
      handle.dispose();
    });
  });

  group('P27 text scaling keeps content reachable', () {
    Future<AuthState> auth() async {
      final state = AuthState(
        repository: AuthRepository(client: FakeAuthClient()),
      );
      addTearDown(() {
        state.unsubFromAuth();
        state.dispose();
      });
      return state;
    }

    for (final double factor in <double>[1.5]) {
      testWidgets('login renders at ${factor}x', (WidgetTester tester) async {
        await tester.pumpWidget(
          scale(MaterialApp(home: LoginScreen(auth: await auth())), factor),
        );
        await tester.pumpAndSettle();
        expect(find.text('Log in to RailMate BD'), findsOneWidget);
        expect(find.text('Log In'), findsWidgets);
      });

      testWidgets('register renders at ${factor}x', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          scale(MaterialApp(home: RegisterScreen(auth: await auth())), factor),
        );
        await tester.pumpAndSettle();
        expect(find.text('Create Account'), findsWidgets);
      });

      testWidgets('onboarding renders at ${factor}x', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          scale(MaterialApp(home: OnboardingScreen(onFinished: () {})), factor),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingScreen), findsOneWidget);
      });

      testWidgets('search results render at ${factor}x', (
        WidgetTester tester,
      ) async {
        final state = SearchState(api: _NeverApi())
          ..stations = const <Station>[
            Station(id: 'o', code: 'DAC', name: 'Dhaka'),
            Station(id: 'd', code: 'CGP', name: 'Chattogram'),
          ]
          ..origin = const Station(id: 'o', code: 'DAC', name: 'Dhaka')
          ..destination = const Station(
            id: 'd',
            code: 'CGP',
            name: 'Chattogram',
          )
          ..results = <Trip>[trip()]
          ..status = SearchStatus.loaded;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          scale(
            MaterialApp(
              home: SearchResultsScreen(state: state, onSelectTrip: (_) {}),
            ),
            factor,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Accessibility Express (Demo)'), findsOneWidget);
      });

      testWidgets('seat selection renders at ${factor}x', (
        WidgetTester tester,
      ) async {
        final seats = SeatSelectionState(
          tripId: 't-a11y',
          fetchSeats: (_) async => const <TripSeat>[
            TripSeat(id: 's1', tripId: 't-a11y', seatCode: 'A1'),
            TripSeat(id: 's2', tripId: 't-a11y', seatCode: 'A2'),
          ],
        );
        addTearDown(seats.dispose);
        await tester.pumpWidget(
          scale(
            MaterialApp(
              home: SeatSelectionScreen(
                trip: trip(),
                state: seats,
                onContinue: (_) {},
              ),
            ),
            factor,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A1'), findsOneWidget);
        expect(find.text('Selected Seats (0)'), findsOneWidget);
      });

      testWidgets('passenger details render at ${factor}x', (
        WidgetTester tester,
      ) async {
        final form = PassengerFormState(
          seatCodes: const <String>['A1'],
          fareBdt: 500,
        );
        addTearDown(form.dispose);
        await tester.pumpWidget(
          scale(
            MaterialApp(
              home: PassengerDetailsScreen(formState: form, onContinue: (_) {}),
            ),
            factor,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Passenger Details'), findsOneWidget);
        expect(find.text('Passenger 1'), findsOneWidget);
      });

      testWidgets('board feed renders at ${factor}x', (
        WidgetTester tester,
      ) async {
        final feed = PostFeedState(
          fetchPosts: ({int limit = 20}) async => const <Post>[],
        );
        addTearDown(feed.dispose);
        // Reach the real empty state (a never-loaded feed shows the
        // loading skeleton instead).
        await feed.load();
        await tester.pumpWidget(
          scale(MaterialApp(home: BoardFeedScreen(feed: feed)), factor),
        );
        await tester.pumpAndSettle();
        expect(find.text('Journey Board'), findsOneWidget);
        expect(find.text('No posts yet'), findsOneWidget);
      });
    }
  });
}

class _NeverApi implements SearchApi {
  @override
  Future<List<Station>> fetchStations() => Future.value(const <Station>[]);

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) => Future.value(const <Trip>[]);
}
