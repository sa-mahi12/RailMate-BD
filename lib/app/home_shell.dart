import 'package:flutter/material.dart';

import '../features/board/post/post_feed_state.dart';
import '../features/board/post/feed_screen.dart';
import '../features/booking/passenger_ui/passenger.dart';
import '../features/booking/passenger_ui/passenger_form_state.dart';
import '../features/booking/payment_ui/payment_state.dart';
import '../features/booking/seat_ui/seat_selection_state.dart';
import '../features/bookings/booking_history_screen.dart';
import '../features/search/home_search_screen.dart';
import '../features/search/models/trip.dart';
import '../features/search/search_state.dart';
import '../features/station_guide/guide_list_screen.dart';
import 'dependencies.dart';
import 'routes.dart';

/// Four-tab bottom-navigation shell (F02 wired, F16 aligns tabs).
///
/// Tabs: Home/Search, My Trips, Board, Guide. Each tab keeps its own
/// [Navigator] (via [_TabNavigator] + per-tab [GlobalKey]) inside an
/// [IndexedStack], so inner routes stack per tab and the system back button
/// pops inner routes first; a back press on a tab root stays in the app
/// (handled in [_onBack]) instead of exiting.
///
/// Every backend call in this shell flows through [dependencies], built once
/// in `main.dart` after real `Supabase.initialize`. Failures surface through
/// each screen's normal error path — no fake rows anywhere.
///
/// Station Guide is reachable two ways: the Guide tab and the guide
/// card/button on the Home tab ([HomeSearchScreen.onStationGuideTap]).
class HomeShell extends StatefulWidget {
  final AppDependencies dependencies;

  const HomeShell({super.key, required this.dependencies});

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

  late final SearchState _searchState = SearchState(
    api: widget.dependencies.searchApi,
  );
  late final PostFeedState _boardFeed = PostFeedState(
    fetchPosts: widget.dependencies.fetchBoardPosts,
  );

  @override
  void initState() {
    super.initState();
    widget.dependencies.auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

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
    final SeatSelectionState seats = SeatSelectionState(
      tripId: trip.id,
      fetchSeats: widget.dependencies.seatFetcher,
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
                            // F07 wires the hosted atomic booking Edge
                            // function call here (auth uid + UUID request id
                            // from PaymentState), then pushes the ticket
                            // route with the confirmed TicketData. Never
                            // fabricate a ticket here.
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
    widget.dependencies.auth.removeListener(_onAuthChanged);
    _searchState.dispose();
    _boardFeed.dispose();
    super.dispose();
  }

  /// Signed-in uid, or null when logged out.
  String? get _uid => widget.dependencies.auth.user?.id;

  @override
  Widget build(BuildContext context) {
    final String? uid = _uid;
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
              root: uid == null
                  ? SignInRequiredScreen(
                      title: 'My Trips',
                      onSignIn: () =>
                          _keys[1].currentState?.pushNamed(AppRoutes.login),
                    )
                  : BookingHistoryScreen(
                      repository: widget.dependencies.historyFor(uid),
                      ownerId: uid,
                    ),
            ),
            _TabNavigator(
              navigatorKey: _keys[2],
              root: BoardFeedScreen(
                feed: _boardFeed,
                onCompose: () {
                  _keys[2].currentState?.pushNamed(
                    AppRoutes.boardCompose,
                    arguments: BoardComposeRouteArgs(userId: uid),
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

/// Genuine signed-out gate for account tabs: explains that sign-in is
/// needed and routes to the login screen. Shown only when logged out —
/// never on a happy path.
class SignInRequiredScreen extends StatelessWidget {
  final String title;
  final VoidCallback onSignIn;

  const SignInRequiredScreen({
    super.key,
    required this.title,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A66),
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_circle_outlined,
                size: 48,
                color: Color(0xFF0E5A66),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sign in to continue',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your bookings live in your account.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A66),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onSignIn,
                child: const Text(
                  'Sign in',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
