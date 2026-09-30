import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:railmate_bd/app/app.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/app/routes.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/login_screen.dart';
import 'package:railmate_bd/features/auth/welcome_screen.dart';
import 'package:railmate_bd/features/board/post/feed_screen.dart';
import 'package:railmate_bd/features/board/post/post_engagement.dart';
import 'package:railmate_bd/features/board/post/post_feed_state.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_form_state.dart';
import 'package:railmate_bd/features/booking/payment_ui/payment_state.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_state.dart';
import 'package:railmate_bd/features/bookings/booking_history.dart';
import 'package:railmate_bd/features/bookings/booking_history_screen.dart';
import 'package:railmate_bd/features/search/ml/trip_ranker.dart'
    show smartRankingUnavailableNote;
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_state.dart';
import 'package:railmate_bd/features/station_guide/guide_webview_screen.dart';
import 'package:railmate_bd/features/station_guide/station_guide.dart';
import 'package:railmate_bd/features/ticket/ticket_data.dart';

import 'f19_fakes.dart';

/// F19 — composition-root integration tests (Worker E, QA/Integration).
///
/// All hermetic: every backend is faked, no network, no secrets, no real
/// Supabase client. What this pins (and `navigation_i01_test.dart` does
/// NOT repeat — that file owns boot-to-tabs + unknown-route):
///
/// * Full boot with `AppDependencies.test`: Home search composition,
///   Home -> guide-list navigation, Bookings gate, Board header, Profile
///   logged-out AND logged-in (fake [AuthState] with stub user).
/// * Booking journey with fakes, one real route object per step:
///   search-results (rankingNote caption) -> seat selection (demo-held
///   disabled) -> passengers -> review -> payment success -> ticket
///   (valid snapshot renders, invalid snapshot errors).
/// * Routes table: wrong-args error screens, guide list -> detail,
///   key-setup, board compose logged-out note, history gate, welcome/login.
/// * Honest backend-missing failures: `submitBooking`/`historyFor` list
///   path throw [StateError] under test deps — no fabricated ticket/rows.
/// * History populated + cancel -> CANCELLED is owned by `history_f09_test`
///   (controller contract); here only route-level wiring is pinned.
/// * `GuideWebViewScreen` is NEVER pumped (platform views); constructor +
///   pure args only, with a documented skip.
///
/// Search states preset `results`/`status` directly instead of calling
/// `SearchState.search()` by design: that path lazily loads the bundled
/// TFLite asset, which has no place in a hermetic composition test.
void main() {
  // ------------------------------------------------------------------
  // A. Full boot with AppDependencies.test.
  // ------------------------------------------------------------------
  group('boot composition (logged out)', () {
    testWidgets('home search composition + guide card navigation', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        RailMateApp(dependencies: f19TestDeps(auth: auth)),
      );
      await tester.pumpAndSettle();

      // Beyond navigation_i01 (which only checks the 'Home' label): the
      // Home tab is the search composition, not a placeholder.
      expect(find.text('Search Trains'), findsOneWidget);
      expect(find.text('Journey date'), findsOneWidget);
      expect(find.text('Station Guide'), findsOneWidget);

      // Home Station Guide promo pushes the guide list inside tab 0.
      // The promo card sits below the fold: scroll it into view first,
      // then tap its InkWell directly (the bare text tap is unreliable
      // inside the nested Row/Expanded layout).
      final Finder promoText = find.text('Station Guide');
      await tester.scrollUntilVisible(promoText, 300.0);
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(of: promoText, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Offline demo guides — DEMONSTRATION ONLY'),
        findsOneWidget,
      );
    });

    testWidgets('bookings gate, board header, profile logged-out', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        RailMateApp(dependencies: f19TestDeps(auth: auth)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bookings').last);
      await tester.pumpAndSettle();
      expect(find.text('Sign in to continue'), findsOneWidget);

      // F19 fix verified: the gate pushes the login route through the tab
      // Navigator WITH AppDependencies, so the real LoginScreen renders
      // (previously fell through to the shared error screen).
      await tester.tap(find.text('Sign in').first);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('App dependencies missing.'), findsNothing);

      await tester.tap(find.text('Board').last);
      await tester.pumpAndSettle();
      expect(find.text('Journey Board'), findsOneWidget);

      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Not signed in'), findsOneWidget);
    });
  });

  group('boot composition (logged in via fake AuthState)', () {
    testWidgets('bookings history error state, board, profile', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        RailMateApp(dependencies: f19TestDeps(auth: auth)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bookings').last);
      await tester.pumpAndSettle();
      // No backend client in test deps: the route builds the REAL
      // BookingHistoryScreen (no fake rows) and its honest load-error
      // state surfaces. Populated + cancel -> CANCELLED logic is owned
      // by history_f09_test (referenced, not duplicated).
      expect(find.text('My bookings'), findsOneWidget);
      expect(find.text('Could not load bookings.'), findsOneWidget);

      await tester.tap(find.text('Board').last);
      await tester.pumpAndSettle();
      expect(find.text('Journey Board'), findsOneWidget);

      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('qa@example.com'), findsOneWidget);
      expect(find.text('Email verified'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('AI key setup'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------
  // B. Honest backend-missing failures (no fabricated tickets/rows).
  // ------------------------------------------------------------------
  group('test-deps backend seams fail loudly', () {
    test(
      'submitBooking throws StateError (shell onSucceeded cannot fake)',
      () async {
        final AuthState auth = await f19AuthState(loggedIn: true);
        addTearDown(auth.dispose);
        final AppDependencies deps = f19TestDeps(auth: auth);
        // home_shell's payment onSucceeded awaits this: under
        // AppDependencies.test it throws StateError (NOT
        // BookingSubmitException, so the shell does not convert it into a
        // ticket or a Booking-failed screen — the failure is loud).
        expect(
          () => deps.submitBooking(
            tripId: 't-padma',
            requestId: 'req-f19-1',
            passengerNames: const <String>['Tanvir Ahmed'],
            seatCodes: const <String>['A1'],
            simulateSuccess: true,
          ),
          throwsStateError,
        );
      },
    );

    test('historyFor list path throws StateError (no fake rows)', () async {
      final AuthState auth = await f19AuthState(loggedIn: true);
      addTearDown(auth.dispose);
      final AppDependencies deps = f19TestDeps(auth: auth);
      final BookingHistoryRepository repo = deps.historyFor('u-f19');
      await expectLater(() => repo.listOwned('u-f19'), throwsStateError);
    });
  });

  // ------------------------------------------------------------------
  // C. Booking journey with fakes (real route objects per step).
  // ------------------------------------------------------------------

  /// Search state with preset results; the TFLite ranker is bypassed by
  /// design (see file doc).
  SearchState loadedSearchState({required String? rankingNote}) {
    final SearchState state = SearchState(
      api: F19SearchApi(stations: f19Stations(), trips: f19Trips()),
    );
    state
      ..stations = f19Stations()
      ..origin = f19Stations()[0]
      ..destination = f19Stations()[1]
      ..results = f19Trips()
      ..status = SearchStatus.loaded
      ..rankingNote = rankingNote;
    return state;
  }

  group('journey: search results route', () {
    testWidgets('fake trips + rankingNote caption; tap selects trip', (
      WidgetTester tester,
    ) async {
      final SearchState state = loadedSearchState(
        rankingNote: smartRankingUnavailableNote,
      );
      addTearDown(state.dispose);
      Trip? selected;
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.searchResults,
            arguments: SearchResultsArgs(
              state: state,
              onSelectTrip: (Trip trip) => selected = trip,
            ),
          ),
        ),
      );
      expect(find.text('Search Results'), findsOneWidget);
      expect(find.text('DEMO Padma Express'), findsOneWidget);
      expect(find.text('DEMO Silk City'), findsOneWidget);
      expect(find.text(smartRankingUnavailableNote), findsOneWidget);

      await tester.tap(find.text('DEMO Padma Express').first);
      await tester.pumpAndSettle();
      expect(selected?.id, 't-padma');
    });

    testWidgets('null rankingNote shows no caption', (
      WidgetTester tester,
    ) async {
      final SearchState state = loadedSearchState(rankingNote: null);
      addTearDown(state.dispose);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.searchResults,
            arguments: SearchResultsArgs(state: state, onSelectTrip: (_) {}),
          ),
        ),
      );
      expect(find.text('DEMO Padma Express'), findsOneWidget);
      expect(find.text(smartRankingUnavailableNote), findsNothing);
    });
  });

  group('journey: seat selection route', () {
    testWidgets('demo-held and booked disabled; continue carries codes', (
      WidgetTester tester,
    ) async {
      final Trip trip = f19Trips().first;
      final SeatSelectionState seats = SeatSelectionState(
        tripId: trip.id,
        fetchSeats: (_) async => f19Seats(),
      );
      addTearDown(seats.dispose);
      List<String>? continued;
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.seatSelection,
            arguments: SeatRouteArgs(
              trip: trip,
              state: seats,
              onContinue: (List<String> codes) => continued = codes,
            ),
          ),
        ),
      );
      expect(find.text('Select Your Seat'), findsOneWidget);
      expect(find.text('Reserved'), findsWidgets);

      // Demo-held (A2) and really-booked (B1) taps select nothing.
      await tester.tap(find.text('A2').first);
      await tester.pump();
      await tester.tap(find.text('B1').first);
      await tester.pump();
      expect(seats.selectedSeatCodes, isEmpty);

      await tester.tap(find.text('A1').first);
      await tester.pump();
      expect(seats.selectedSeatCodes, <String>['A1']);
      expect(find.text('Selected Seats (1)'), findsOneWidget);

      await tester.tap(find.text('Continue to Passenger Details'));
      await tester.pumpAndSettle();
      expect(continued, <String>['A1']);
    });
  });

  /// Passenger form pre-filled through the real state API.
  PassengerFormState validPassengerForm() {
    final PassengerFormState form = PassengerFormState(
      seatCodes: const <String>['A1'],
      fareBdt: 500,
    );
    form
      ..updateName(0, 'Tanvir Ahmed')
      ..updateType(0, PassengerType.adult)
      ..setContactMobile('01712345678');
    return form;
  }

  group('journey: passengers -> review -> payment', () {
    testWidgets('passenger details continue carries validated rows', (
      WidgetTester tester,
    ) async {
      final PassengerFormState form = PassengerFormState(
        seatCodes: const <String>['A1'],
        fareBdt: 500,
      );
      addTearDown(form.dispose);
      List<Passenger>? continued;
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.passengerDetails,
            arguments: PassengerRouteArgs(
              formState: form,
              onContinue: (List<Passenger> rows) => continued = rows,
            ),
          ),
        ),
      );
      expect(find.text('Passenger Details'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Tanvir Ahmed');
      await tester.pump();
      await tester.tap(find.text('Select type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adult (A)').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '01712345678');
      await tester.pumpAndSettle();

      expect(form.isValid, isTrue);
      // Continue sits at the end of the ListView (below the fold and
      // outside the cache extent until scrolled): drag the list, then tap
      // the now-visible button. (scrollUntilVisible is flaky here — the
      // button transiently matches twice mid-scroll.)
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();
      expect(continued, hasLength(1));
      expect(continued!.single.name, 'Tanvir Ahmed');
      expect(continued!.single.type, PassengerType.adult);
      expect(continued!.single.seatCode, 'A1');
    });

    testWidgets('review confirm fires after accepting terms', (
      WidgetTester tester,
    ) async {
      final PassengerFormState form = validPassengerForm();
      addTearDown(form.dispose);
      var confirmed = false;
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.review,
            arguments: ReviewRouteArgs(
              formState: form,
              onEditJourney: () {},
              onEditPassengers: () {},
              onConfirm: () => confirmed = true,
            ),
          ),
        ),
      );
      expect(find.text('Booking Review'), findsOneWidget);
      expect(find.text('Tanvir Ahmed'), findsOneWidget);

      await tester.scrollUntilVisible(find.byType(Checkbox), 200.0);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Confirm Booking'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('payment success fires onSucceeded exactly once', (
      WidgetTester tester,
    ) async {
      final PassengerFormState form = validPassengerForm();
      addTearDown(form.dispose);
      final PaymentState payment = PaymentState(
        requestId: 'req-f19-1',
        totalBdt: form.totalBdt,
        fareBreakdown: form.fareBreakdown,
      );
      addTearDown(payment.dispose);
      var succeededCalls = 0;
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.payment,
            arguments: PaymentRouteArgs(
              formState: form,
              paymentState: payment,
              onSucceeded: () => succeededCalls++,
            ),
          ),
        ),
      );
      expect(find.text('Payment'), findsWidgets);

      await tester.tap(find.text('Simulate success'));
      await tester.pumpAndSettle();
      expect(succeededCalls, 1);
      expect(payment.status, PaymentStatus.succeeded);
      expect(
        find.text('Payment simulated: SUCCESS. Booking intent created.'),
        findsOneWidget,
      );
    });
  });

  group('journey: ticket route', () {
    testWidgets('valid snapshot renders ref, QR, download, demo banner', (
      WidgetTester tester,
    ) async {
      final PassengerFormState form = validPassengerForm();
      addTearDown(form.dispose);
      final TicketData ticket = TicketData.fromForm(
        form: form,
        bookingReference: 'BDR5F9K3',
        trainLabel: 'DEMO Padma Express',
        fromLabel: 'DAC',
        toLabel: 'CGP',
        departLabel: '2026-10-15T08:00:00',
      );
      expect(ticket.isValid, isTrue);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.ticket,
            arguments: TicketRouteArgs(ticket: ticket),
          ),
        ),
      );
      expect(find.text('Ref: BDR5F9K3'), findsOneWidget);
      expect(find.text(TicketData.demoBanner), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      // Download card is below the fold: scroll first (lazy list).
      await tester.scrollUntilVisible(find.text('Download demo PDF'), 200.0);
      await tester.pumpAndSettle();
      expect(find.text('Download demo PDF'), findsOneWidget);
    });

    testWidgets('invalid snapshot errors with no QR or download', (
      WidgetTester tester,
    ) async {
      final TicketData bad = TicketData(
        bookingReference: 'bad',
        passengers: const <Passenger>[
          Passenger(
            name: 'Tanvir Ahmed',
            type: PassengerType.adult,
            seatCode: 'A1',
          ),
        ],
        fareBreakdown: const <String, int>{
          'passengerCount': 1,
          'farePerSeat': 500,
          'baseFare': 500,
          'serviceCharge': 40,
          'total': 540,
        },
        totalBdt: 540,
      );
      expect(bad.isValid, isFalse);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.ticket,
            arguments: TicketRouteArgs(ticket: bad),
          ),
        ),
      );
      expect(find.text('Ticket unavailable'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Download demo PDF'), findsNothing);
    });
  });

  group('routes table: wrong-args error screens', () {
    testWidgets('each journey step names its missing args', (
      WidgetTester tester,
    ) async {
      final Map<String, String> cases = <String, String>{
        AppRoutes.searchResults: 'Search results need a search state.',
        AppRoutes.seatSelection: 'Seat selection needs a trip.',
        AppRoutes.passengerDetails: 'Passenger details need a form state.',
        AppRoutes.review: 'Review needs a form state.',
        AppRoutes.payment: 'Payment needs a form state.',
        AppRoutes.ticket: 'Ticket needs a ticket snapshot.',
        AppRoutes.guideDetail: 'Station guide needs a guide entry.',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        await pumpAppRoute(
          tester,
          AppRoutes.onGenerateRoute(RouteSettings(name: entry.key)),
        );
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'route ${entry.key}',
        );
      }
    });
  });

  // ------------------------------------------------------------------
  // D. History route wiring (logic owned by history_f09_test).
  // ------------------------------------------------------------------
  group('history route wiring', () {
    testWidgets('logged out builds the My Trips sign-in gate', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.history),
          dependencies: f19TestDeps(auth: auth),
        ),
      );
      expect(find.text('My Trips'), findsOneWidget);
      expect(find.text('Sign in to continue'), findsOneWidget);
    });

    testWidgets('logged in builds the screen with honest load error', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: true);
      addTearDown(auth.dispose);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.history),
          dependencies: f19TestDeps(auth: auth),
        ),
      );
      // Route passes dependencies.historyFor(uid) (null-client test deps:
      // load fails loudly, no fake rows) into the real screen.
      expect(find.text('My bookings'), findsOneWidget);
      expect(find.text('Could not load bookings.'), findsOneWidget);
    });

    testWidgets('route target screen renders a fake repository row', (
      WidgetTester tester,
    ) async {
      // history_f09_test owns populated/cancel logic at controller level
      // and never pumps the widget; this smoke test proves the screen the
      // route constructs renders a real repository shape.
      final BookingHistoryRepository repo = BookingHistoryRepository(
        fetchRows: (_) async => <Map<String, dynamic>>[f19BookingRow()],
        cancelRpc: ({
          required String ownerId,
          required String bookingId,
        }) async => true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BookingHistoryScreen(repository: repo, ownerId: 'u-f19'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My bookings'), findsOneWidget);
      expect(find.text('Ref: b1'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------
  // E. Board feed, compose, guide, key setup, welcome/login.
  // ------------------------------------------------------------------
  group('board composition', () {
    testWidgets('fake posts render; engagement hidden when seams null', (
      WidgetTester tester,
    ) async {
      final PostFeedState feed = PostFeedState(
        fetchPosts: ({int limit = PostFeedState.defaultLimit}) async =>
            f19Posts(),
      );
      addTearDown(feed.dispose);
      await feed.load();
      await tester.pumpWidget(MaterialApp(home: BoardFeedScreen(feed: feed)));
      await tester.pumpAndSettle();
      expect(find.text('Morning run to DAC was smooth. DEMO.'), findsOneWidget);
      expect(find.text('CGP platform tips. DEMO.'), findsOneWidget);
      // All six reaction/rating seams null -> no engagement section.
      expect(find.byType(PostEngagement), findsNothing);
    });

    testWidgets('compose logged out shows setup note; logged in hides it', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      final AppDependencies deps = f19TestDeps(auth: auth);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.boardCompose),
          dependencies: deps,
        ),
      );
      expect(find.text('New post'), findsOneWidget);
      expect(
        find.text(
          'Sign-in required to publish. You can still draft text and use Improve Wording below.',
        ),
        findsOneWidget,
      );

      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(
            name: AppRoutes.boardCompose,
            arguments: BoardComposeRouteArgs(userId: 'u-f19'),
          ),
          dependencies: deps,
        ),
      );
      expect(find.text('New post'), findsOneWidget);
      expect(
        find.text(
          'Sign-in required to publish. You can still draft text and use Improve Wording below.',
        ),
        findsNothing,
      );
      expect(find.text('Continue'), findsOneWidget);
    });
  });

  group('guide composition', () {
    testWidgets('guide list navigates to detail (WebView not tapped)', (
      WidgetTester tester,
    ) async {
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(const RouteSettings(name: AppRoutes.guide)),
      );
      expect(find.text('Station Guide'), findsWidgets);
      await tester.tap(find.text('Dhaka').first);
      await tester.pumpAndSettle();
      expect(find.text('Dhaka (DAC)'), findsOneWidget);
      // Entry point present; the WebView screen itself is never pumped
      // (needs platform views) — see the construction-only test below.
      expect(find.text('Open interactive guide'), findsOneWidget);
    });

    testWidgets('guide detail route builds the right station', (
      WidgetTester tester,
    ) async {
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.guideDetail,
            arguments: GuideDetailRouteArgs(guide: demoStationGuides[1]),
          ),
        ),
      );
      expect(find.text('Chattogram (CGP)'), findsOneWidget);
    });

    test('GuideWebViewScreen construction-only (rendering skipped)', () {
      // Honest skip: GuideWebViewScreen builds a WebViewController in
      // initState, which needs platform views unavailable in widget tests.
      // Pinned here: constructor/args shape + pure query helpers only.
      // (No `const`: demoStationGuides[0] is not a constant expression.)
      final GuideWebViewScreen screen = GuideWebViewScreen(
        guide: demoStationGuides[0],
      );
      expect(screen.guide.stationCode, 'DAC');
      expect(guideStationQuery('cgp'), '?station=CGP');
      expect(normalizeGuideStationCode('   '), 'DAC');
      expect(guideAssetPath, 'web-guide/index.html');
    });
  });

  group('key setup + entry routes', () {
    testWidgets('key setup route renders with mocked secure storage', (
      WidgetTester tester,
    ) async {
      // KeySetupScreen reads vault.hasKey() in initState through
      // flutter_secure_storage; the mock channel keeps it hermetic.
      const MethodChannel channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall call,
      ) async {
        if (call.method == 'containsKey') return false;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.keySetup),
          dependencies: f19TestDeps(auth: auth),
        ),
      );
      expect(find.text('AI Settings'), findsOneWidget);
      expect(find.text('OpenRouter key'), findsOneWidget);
      expect(find.text('Send my key with this request only'), findsOneWidget);
    });

    testWidgets('welcome and login routes build their screens', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await f19AuthState(loggedIn: false);
      addTearDown(auth.dispose);
      final AppDependencies deps = f19TestDeps(auth: auth);
      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.welcome),
          dependencies: deps,
        ),
      );
      expect(find.byType(WelcomeScreen), findsOneWidget);

      await pumpAppRoute(
        tester,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.login),
          dependencies: deps,
        ),
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
