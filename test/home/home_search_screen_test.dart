import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/design.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/search/home/home_sections.dart';
import 'package:railmate_bd/features/search/home/recent_searches_store.dart';
import 'package:railmate_bd/features/search/home/upcoming_booking.dart';
import 'package:railmate_bd/features/search/home_search_screen.dart';
import 'package:railmate_bd/features/search/search_repository.dart';
import 'package:railmate_bd/features/search/search_state.dart';

import 'home_test_fakes.dart';

/// Fixed clock so every greeting/date assertion is deterministic.
DateTime fixedNow() => DateTime(2026, 10, 2, 15, 30); // Friday afternoon

const String arrow = ' \u2192';

Widget wrap(Widget child, {bool reducedMotion = false}) {
  return MaterialApp(
    home: MotionGate(overrideReduced: reducedMotion, child: child),
  );
}

/// Scrolls [finder] into view before tapping: Home is a long scroll and the
/// test viewport is 800x600.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A row inside the recent-searches section (the same text can also appear as
/// a popular-route caption).
Finder recentRow(String label) {
  return find.descendant(
    of: find.byType(RecentSearchesSection),
    matching: find.text(label),
  );
}

void main() {
  group('P10 Home greeting', () {
    testWidgets('greets the signed-in account by name (real local hour)', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await signedInAuth(fullName: 'Nabila');
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(
            state: SearchState(api: FakeSearchApi()),
            auth: auth,
            clock: fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Good afternoon, Nabila'), findsOneWidget);
      expect(find.text('Where are you going today?'), findsOneWidget);
    });

    testWidgets('evening hour renders the evening greeting', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await signedInAuth(username: 'nabila');
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(
            state: SearchState(api: FakeSearchApi()),
            auth: auth,
            clock: () => DateTime(2026, 10, 2, 19),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Good evening, @nabila'), findsOneWidget);
    });

    testWidgets('signed out renders the neutral greeting, no invented name', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await signedOutAuth();
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(
            state: SearchState(api: FakeSearchApi()),
            auth: auth,
            clock: fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to RailMate BD'), findsOneWidget);
      expect(find.textContaining('Good '), findsNothing);
    });
  });

  group('P10 popular demo routes', () {
    testWidgets('resolves shortcuts from the live station list and prefills', (
      WidgetTester tester,
    ) async {
      final SearchState state = SearchState(
        api: FakeSearchApi(
          stations: const [dhaka, chattogram, sylhet, rajshahi, khulna],
        ),
      );
      await tester.pumpWidget(
        wrap(HomeSearchScreen(state: state, clock: fixedNow)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Popular demo routes'), findsOneWidget);
      expect(find.text('DAC$arrow CGP'), findsWidgets);

      await tapVisible(tester, find.text('DAC$arrow CGP').first);
      expect(state.origin?.code, 'DAC');
      expect(state.destination?.code, 'CGP');
    });

    testWidgets('missing catalog renders the honest unavailable state', (
      WidgetTester tester,
    ) async {
      final FakeSearchApi api = FakeSearchApi(
        stationError: const NetworkError('offline'),
      );
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(
            state: SearchState(api: api),
            clock: fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('catalogue loads'), findsOneWidget);
      // No invented station codes anywhere.
      expect(find.textContaining('DAC'), findsNothing);
      // Retry re-queries the real repository.
      await tapVisible(tester, find.text('Retry'));
      expect(api.stationLoads, greaterThanOrEqualTo(2));
    });
  });

  group('P10 recent searches', () {
    testWidgets('records a real search and restores it; clear-all empties', (
      WidgetTester tester,
    ) async {
      final SearchState state = SearchState(
        api: FakeSearchApi(
          stations: const [dhaka, chattogram, sylhet, rajshahi, khulna],
        ),
      );
      await tester.pumpWidget(
        wrap(HomeSearchScreen(state: state, clock: fixedNow)),
      );
      await tester.pumpAndSettle();

      // Empty and never preseeded.
      expect(find.text('No recent searches'), findsOneWidget);

      await tapVisible(tester, find.text('DAC$arrow CGP').first);
      await tapVisible(tester, find.text('Search Trains'));
      await tester.pumpAndSettle();

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Dhaka$arrow Chattogram'), findsWidgets);

      // Swap, then restore the recorded route from the recent row.
      await tapVisible(tester, find.byIcon(Icons.swap_vert));
      await tester.pumpAndSettle();
      expect(state.origin?.code, 'CGP');
      await tapVisible(tester, recentRow('Dhaka$arrow Chattogram'));
      expect(state.origin?.code, 'DAC');
      expect(state.destination?.code, 'CGP');

      await tapVisible(tester, find.text('Clear all'));
      expect(find.text('No recent searches'), findsOneWidget);
    });

    testWidgets('an injected store keeps history across screens', (
      WidgetTester tester,
    ) async {
      final RecentSearchStore store = InMemoryRecentSearchStore(<RecentSearch>[
        RecentSearch(
          originId: dhaka.id,
          destinationId: khulna.id,
          originLabel: 'Dhaka',
          destinationLabel: 'Khulna',
          date: fixedNow(),
        ),
      ]);
      final SearchState state = SearchState(
        api: FakeSearchApi(
          stations: const [dhaka, chattogram, sylhet, rajshahi, khulna],
        ),
      );
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(
            state: state,
            recentSearches: store,
            clock: fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(recentRow('Dhaka$arrow Khulna'), findsOneWidget);
      await tapVisible(tester, recentRow('Dhaka$arrow Khulna'));
      expect(state.origin?.code, 'DAC');
      expect(state.destination?.code, 'KHL');
    });
  });

  group('P10 upcoming booking seam', () {
    final UpcomingBooking booking = UpcomingBooking(
      reference: 'A1B2C3D4',
      originLabel: 'DAC',
      destinationLabel: 'KHL',
      serviceLabel: 'Sundarban Express (Demo)',
      departureAt: DateTime(2026, 10, 15, 8, 15),
      seatCodes: const <String>['A1'],
    );

    testWidgets('renders a real booking from the loader', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          UpcomingBookingSection(
            signedIn: true,
            loader: () async => booking,
            onViewBooking: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your next trip'), findsOneWidget);
      expect(find.text('DAC$arrow KHL'), findsOneWidget);
      expect(find.text('A1B2C3D4'), findsOneWidget);
      expect(find.textContaining('Sundarban Express'), findsOneWidget);
      expect(find.text('View ticket / details'), findsOneWidget);
      expect(find.textContaining('not valid for travel'), findsOneWidget);
    });

    testWidgets('loader returning null shows the honest empty state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(UpcomingBookingSection(signedIn: true, loader: () async => null)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No upcoming bookings'), findsOneWidget);
      expect(find.text('Your next trip'), findsNothing);
    });

    testWidgets('loader failure is a failure, not "no bookings"', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          UpcomingBookingSection(
            signedIn: true,
            loader: () async => throw StateError('boom'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load your bookings'), findsOneWidget);
      expect(find.text('No upcoming bookings'), findsNothing);
    });

    testWidgets('no loader (unwired) fabricates nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const UpcomingBookingSection(signedIn: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No upcoming bookings'), findsOneWidget);
      expect(find.text('Your next trip'), findsNothing);
    });

    testWidgets('signed out explains sign-in instead of faking a ticket', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(UpcomingBookingSection(signedIn: false, onSignIn: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in to see your tickets'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('P10 date horizon and demo notice', () {
    test('demo horizon is today..today+20', () {
      expect(
        demoHorizonLastDate(DateTime(2026, 10, 2, 23, 59)),
        DateTime(2026, 10, 22),
      );
      expect(kDemoBookingHorizonDays, 20);
    });

    testWidgets('picker horizon is stated and searches beyond it are blocked', (
      WidgetTester tester,
    ) async {
      final FakeSearchApi api = FakeSearchApi(
        stations: const [dhaka, chattogram],
      );
      final SearchState state = SearchState(api: api);
      await tester.pumpWidget(
        wrap(HomeSearchScreen(state: state, clock: fixedNow)),
      );
      await tester.pumpAndSettle();
      // Picker is bounded to today+20 days (hosted demo horizon).
      expect(find.text('Up to 22 Oct, 2026'), findsOneWidget);

      state.selectOrigin(dhaka);
      state.selectDestination(chattogram);
      state.selectDate(DateTime(2026, 11, 30));
      await tapVisible(tester, find.text('Search Trains'));
      await tester.pumpAndSettle();

      expect(
        find.text('Demo schedules are available for the next 20 days.'),
        findsOneWidget,
      );
      expect(api.searches, 0, reason: 'no repository call past the horizon');
    });

    testWidgets('demo-data notice states the pack copy', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(
            state: SearchState(api: FakeSearchApi()),
            clock: fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('About the demo data'));
      expect(
        find.text(
          'Schedules, fares and seat occupancy shown in RailMate BD are '
          'demonstration data.',
        ),
        findsOneWidget,
      );
    });
  });

  group('P10 reduced motion', () {
    testWidgets('content renders immediately with reduced motion', (
      WidgetTester tester,
    ) async {
      final SearchState state = SearchState(
        api: FakeSearchApi(
          stations: const [dhaka, chattogram, sylhet, rajshahi, khulna],
        ),
      );
      await tester.pumpWidget(
        wrap(
          HomeSearchScreen(state: state, clock: fixedNow),
          reducedMotion: true,
        ),
      );
      // First frames only: reduced motion skips entrance delays/staggers, so
      // the whole Home content is already in its final state.
      await tester.pump();
      await tester.pump();
      expect(find.text('Popular demo routes'), findsOneWidget);
      expect(find.text('No recent searches'), findsOneWidget);
      expect(find.byType(FadeSlideIn), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
