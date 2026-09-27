import 'package:flutter/material.dart';

import '../features/board/post/post_feed_state.dart';
import '../features/board/post/feed_screen.dart';
import '../features/booking/passenger_ui/passenger.dart';
import '../features/booking/passenger_ui/passenger_form_state.dart';
import '../features/booking/payment_ui/payment_state.dart';
import '../features/booking/seat_ui/seat_selection_state.dart';
import '../features/search/home_search_screen.dart';
import '../features/search/models/station.dart';
import '../features/search/models/trip.dart';
import '../features/search/search_repository.dart';
import '../features/search/search_state.dart';
import '../features/station_guide/guide_list_screen.dart';
import 'routes.dart';

/// Four-tab bottom-navigation shell (I01, R-21).
///
/// Tabs: Home/Search, My Trips, Board, Guide. Each tab keeps its own
/// [Navigator] (via [_TabNavigator] + per-tab [GlobalKey]) inside an
/// [IndexedStack], so inner routes stack per tab and the system back button
/// pops inner routes first; a back press on a tab root stays in the app
/// (handled in [_onBack]) instead of exiting.
///
/// Station Guide is reachable two ways: the Guide tab and the guide
/// card/button on the Home tab ([HomeSearchScreen.onStationGuideTap]).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const Color _teal = Color(0xFF0E5A66);

  int _index = 0;

  final List<GlobalKey<NavigatorState>> _keys =
      List<GlobalKey<NavigatorState>>.generate(
        4,
        (_) => GlobalKey<NavigatorState>(),
      );

  // Tab-owned state. SearchState needs a SearchApi; no Supabase client is
  // wired at shell level yet (coordinator/startup step), so the tab uses an
  // explicitly unconfigured API that reports "setup required" through the
  // screen's normal error path.
  // TODO(SUPABASE-SEARCH): replace [_UnconfiguredSearchApi] with
  // SupabaseSearchApi once Supabase.initialize is wired at startup.
  late final SearchState _searchState = SearchState(
    api: const _UnconfiguredSearchApi(),
  );
  late final PostFeedState _boardFeed = PostFeedState(
    fetchPosts: ({int limit = PostFeedState.defaultLimit}) =>
        throw const NetworkError('Board feed needs hosted Supabase wiring.'),
  );

  void _selectTab(int index) {
    if (index == _index) {
      // Re-tapping the active tab pops it back to its root.
      _keys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = index);
  }

  /// Per-tab back handling: pop the active tab's inner routes first; when
  /// already at a tab root, stay in the app (return without popping).
  void _onBack(bool didPop) {
    if (didPop) return;
    final NavigatorState? nav = _keys[_index].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
    // Tab root: do nothing — the user stays in the app.
  }

  /// Booking journey chained inside one tab's Navigator: results → seat →
  /// passengers → review → payment. Every step forwards host-owned state
  /// objects built from the selected trip + user input (no fake data); each
  /// screen's own back control pops one step. The booking submit after a
  /// simulated-success payment needs the hosted Edge function + auth uid and
  /// lands on an explicit setup placeholder (TODO below).
  void _openSeatSelection({required int tab, required Trip trip}) {
    // TODO(SUPABASE-SEATS): replace the throwing fetcher with the hosted
    // `public.trip_seats` query once Supabase wiring lands at startup.
    final SeatSelectionState seats = SeatSelectionState(
      tripId: trip.id,
      fetchSeats: (String tripId) => throw const NetworkError(
        'Seat inventory needs hosted Supabase wiring (see TODO in home_shell.dart).',
      ),
    );
    _keys[tab].currentState?.pushNamed(
      AppRoutes.seatSelection,
      arguments: SeatRouteArgs(
        trip: trip,
        state: seats,
        onContinue: (List<String> seatCodes) {
          final PassengerFormState form = PassengerFormState(
            seatCodes: seatCodes,
            fareBdt: trip.fareBdt,
          );
          _keys[tab].currentState?.pushNamed(
            AppRoutes.passengerDetails,
            arguments: PassengerRouteArgs(
              formState: form,
              onContinue: (List<Passenger> _) {
                _keys[tab].currentState?.pushNamed(
                  AppRoutes.review,
                  arguments: ReviewRouteArgs(
                    formState: form,
                    onEditJourney: () => _keys[tab].currentState?.popUntil(
                      (route) => route.isFirst,
                    ),
                    onEditPassengers: () => _keys[tab].currentState?.pop(),
                    onConfirm: () {
                      _keys[tab].currentState?.pushNamed(
                        AppRoutes.payment,
                        arguments: PaymentRouteArgs(
                          formState: form,
                          paymentState: PaymentState(
                            totalBdt: form.totalBdt,
                            fareBreakdown: form.fareBreakdown,
                          ),
                          onSucceeded: () {
                            // TODO(BOOKING-LANE): call the hosted atomic
                            // booking Edge function with the auth uid, then
                            // push the ticket route with the confirmed
                            // TicketData. Never fabricate a ticket here.
                            _keys[tab].currentState?.push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SetupRequiredScreen(
                                  title: 'Booking',
                                  missing: 'Booking submit needs the hosted atomic-booking function and the signed-in account id (see TODO in home_shell.dart). Payment simulation succeeded; no booking was created.',
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchState.dispose();
    _boardFeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _TabNavigator(
              navigatorKey: _keys[0],
              root: HomeSearchScreen(
                state: _searchState,
                onSearchSubmitted: () {
                  _keys[0].currentState?.pushNamed(
                    AppRoutes.searchResults,
                    arguments: SearchResultsArgs(
                      state: _searchState,
                      onSelectTrip: (Trip trip) =>
                          _openSeatSelection(tab: 0, trip: trip),
                    ),
                  );
                },
                onStationGuideTap: () {
                  _keys[0].currentState?.pushNamed(AppRoutes.guide);
                },
              ),
            ),
            _TabNavigator(
              navigatorKey: _keys[1],
              // TODO(AUTH-UID): replace with BookingHistoryScreen once the
              // signed-in uid + BookingHistoryRepository are available.
              root: const SetupRequiredScreen(
                title: 'My Trips',
                missing: 'Booking history needs the signed-in account id and hosted Supabase wiring (see TODO in home_shell.dart).',
              ),
            ),
            _TabNavigator(
              navigatorKey: _keys[2],
              root: BoardFeedScreen(
                feed: _boardFeed,
                onCompose: () {
                  _keys[2].currentState?.pushNamed(
                    AppRoutes.boardCompose,
                    // Null uid: draft + AI Improve Wording stay usable; the
                    // submit path shows its setup note (see BoardComposeHost).
                    // TODO(AUTH-UID): pass the signed-in uid here.
                    arguments: const BoardComposeRouteArgs(),
                  );
                },
              ),
            ),
            _TabNavigator(
              navigatorKey: _keys[3],
              root: const GuideListScreen(),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: _selectTab,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: _teal,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Home'),
            BottomNavigationBarItem(
              icon: Icon(Icons.confirmation_number_outlined),
              label: 'My Trips',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.forum_outlined),
              label: 'Board',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              label: 'Guide',
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab's nested [Navigator]. The tab root renders directly; deeper pushes
/// resolve through the central [AppRoutes.onGenerateRoute] table (unknown
/// names land on the shared error screen, which always has a pop path).
class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  const _TabNavigator({required this.navigatorKey, required this.root});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == Navigator.defaultRouteName) {
          return MaterialPageRoute<void>(builder: (_) => root);
        }
        return AppRoutes.onGenerateRoute(settings);
      },
    );
  }
}

/// Explicitly unconfigured [SearchApi]: throws [NetworkError] with a setup
/// message instead of returning fake stations/trips. Lets HomeSearchScreen
/// render its normal error/empty states until real Supabase wiring lands.
class _UnconfiguredSearchApi implements SearchApi {
  const _UnconfiguredSearchApi();

  static const NetworkError _setup = NetworkError(
    'Trip search needs hosted Supabase wiring (see TODO in home_shell.dart).',
  );

  @override
  Future<List<Station>> fetchStations() => throw _setup;

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) => throw _setup;
}
