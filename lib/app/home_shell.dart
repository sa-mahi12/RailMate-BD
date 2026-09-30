import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../features/board/post/post.dart';
import '../features/board/post/post_feed_realtime.dart';
import '../features/board/post/post_feed_state.dart';
import '../features/board/post/feed_screen.dart';
import '../features/booking/passenger_ui/passenger.dart';
import '../features/booking/passenger_ui/passenger_form_state.dart';
import '../features/booking/payment_ui/payment_state.dart';
import '../features/booking/seat_ui/seat_selection_state.dart';
import '../features/bookings/booking_history_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/home_search_screen.dart';
import '../features/search/models/trip.dart';
import '../features/search/search_state.dart';
import '../features/ticket/ticket_data.dart';
import 'dependencies.dart';
import 'routes.dart';

/// Four-tab bottom-navigation shell (F02 wired, F16 aligns tabs).
///
/// Tabs: Home/Search, Bookings, Board, Profile (navigation contract). Each
/// tab keeps its own [Navigator] (via [_TabNavigator] + per-tab [GlobalKey])
/// inside an [IndexedStack], so inner routes stack per tab and the system
/// back button pops inner routes first; a back press on a tab root stays in
/// the app (handled in [_onBack]) instead of exiting.
///
/// Every backend call in this shell flows through [dependencies], built once
/// in `main.dart` after real `Supabase.initialize`. Failures surface through
/// each screen's normal error path — no fake rows anywhere.
///
/// Station Guide is reachable from the guide card/button on the Home tab
/// ([HomeSearchScreen.onStationGuideTap]) plus its named routes — it is not
/// a bottom tab (F16).
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
    graphqlClient: widget.dependencies.graphql,
  );
  late final PostFeedState _boardFeed = PostFeedState(
    fetchPosts: widget.dependencies.fetchBoardPosts,
    fetchPage: widget.dependencies.fetchBoardPostPage,
  );

  /// F13 live-update subscription for the board feed (transport-free seam:
  /// the shell maps the channel into [BoardPostEvent]s).
  final BoardPostFeedRealtime _boardRealtime = BoardPostFeedRealtime();
  StreamController<BoardPostEvent>? _boardEvents;
  RealtimeChannel? _boardChannel;

  @override
  void initState() {
    super.initState();
    widget.dependencies.auth.addListener(_onAuthChanged);
    _subscribeBoardRealtime();
  }

  /// Subscribes to `postgres_changes` on `public.posts` so inserts, updates
  /// and deletes from other clients merge into [_boardFeed] without
  /// pull-to-refresh. Null client (widget tests, unwired hosts) means an
  /// honest non-live list: no channel is opened and no rows are fabricated.
  void _subscribeBoardRealtime() {
    final SupabaseClient? client = widget.dependencies.client;
    if (client == null) return;
    final StreamController<BoardPostEvent> events =
        StreamController<BoardPostEvent>.broadcast();
    _boardEvents = events;
    final RealtimeChannel channel = client.channel('public:board-posts');
    _boardChannel = channel;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: (PostgresChangePayload payload) {
            if (_boardChannel == null) return;
            final BoardPostEvent? event = _mapBoardPayload(payload);
            if (event != null) events.add(event);
          },
        )
        .subscribe();
    unawaited(
      _boardRealtime.subscribe(
        stream: events.stream,
        onEvent: (BoardPostEvent event) {
          if (!mounted) return;
          applyPostEventToFeed(_boardFeed, event);
        },
      ),
    );
  }

  /// Maps one realtime payload onto a [BoardPostEvent]; returns null when
  /// the payload carries no usable row (malformed payloads are dropped,
  /// never synthesised into posts).
  BoardPostEvent? _mapBoardPayload(PostgresChangePayload payload) {
    final String eventId = payload.commitTimestamp.toIso8601String();
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        if (payload.newRecord.isEmpty) return null;
        try {
          final Post post = Post.fromMap(
            Map<String, dynamic>.from(payload.newRecord),
          );
          return BoardPostEvent(
            eventId: eventId,
            kind: payload.eventType == PostgresChangeEvent.insert
                ? BoardPostEventKind.insert
                : BoardPostEventKind.update,
            post: post,
          );
        } catch (_) {
          return null;
        }
      case PostgresChangeEvent.delete:
        final Object? id = payload.oldRecord['id'];
        if (id == null) return null;
        return BoardPostEvent(
          eventId: eventId,
          kind: BoardPostEventKind.delete,
          postId: id.toString(),
        );
      default:
        return null;
    }
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
  /// screen's own back control pops one step. After a simulated-success
  /// payment the host submits the atomic booking through the deployed
  /// `book-trip` Edge Function (F07) with a UUID idempotency key, then
  /// pushes the ticket route with the confirmed [TicketData]. Failures land
  /// on an explicit error screen — a ticket is never fabricated.
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
                      // UUID idempotency key: the Edge rejects the legacy
                      // `pay-<microseconds>` simulation keys, and retries of
                      // this payment reuse the same key (server-side
                      // idempotency — a retry never double-books).
                      final PaymentState paymentState = PaymentState(
                        requestId: const Uuid().v4(),
                        totalBdt: form.totalBdt,
                        fareBreakdown: form.fareBreakdown,
                      );
                      _keys[tab].currentState?.pushNamed(
                        AppRoutes.payment,
                        arguments: PaymentRouteArgs(
                          formState: form,
                          paymentState: paymentState,
                          onSucceeded: () async {
                            final nav = _keys[tab].currentState;
                            if (nav == null) return;
                            try {
                              final String bookingId = await widget.dependencies
                                  .submitBooking(
                                    tripId: trip.id,
                                    requestId: paymentState.requestId,
                                    passengerNames: <String>[
                                      for (final Passenger p in form.passengers)
                                        p.name,
                                    ],
                                    seatCodes: List<String>.of(form.seatCodes),
                                    simulateSuccess: true,
                                  );
                              nav.pushNamed(
                                AppRoutes.ticket,
                                arguments: TicketRouteArgs(
                                  ticket: TicketData.fromForm(
                                    form: form,
                                    bookingReference:
                                        displayReferenceForBookingId(bookingId),
                                    trainLabel: trip.trainName,
                                    fromLabel: trip.originStationId,
                                    toLabel: trip.destinationStationId,
                                    departLabel: trip.departureAt
                                        .toIso8601String(),
                                  ),
                                ),
                              );
                            } on BookingSubmitException catch (e) {
                              // Genuine failure: taken seats refresh from
                              // live inventory; the user reselects. No
                              // ticket is fabricated on any path.
                              if (e.code == 'SEAT_UNAVAILABLE') {
                                await seats.revalidate();
                              }
                              nav.push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SetupRequiredScreen(
                                    title: 'Booking failed',
                                    missing: e.message,
                                  ),
                                ),
                              );
                            }
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
    // Tear down realtime first so no late event touches the feed: stop the
    // channel, close the event bridge, then dispose the dedupe seam.
    final RealtimeChannel? channel = _boardChannel;
    _boardChannel = null;
    final SupabaseClient? client = widget.dependencies.client;
    if (channel != null && client != null) {
      unawaited(client.removeChannel(channel));
    }
    unawaited(_boardEvents?.close());
    _boardEvents = null;
    unawaited(_boardRealtime.dispose());
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
              dependencies: widget.dependencies,
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
              dependencies: widget.dependencies,
              root: uid == null
                  ? SignInRequiredScreen(
                      title: 'Bookings',
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
              dependencies: widget.dependencies,
              root: BoardFeedScreen(
                feed: _boardFeed,
                imageUrlFor: widget.dependencies.boardImageUrl,
                // F13b engagement seams: per-post reactions/ratings fed by
                // the production closures; signed-out readers (uid null)
                // see aggregates read-only.
                currentUserId: uid,
                fetchReactions: widget.dependencies.fetchBoardReactions,
                upsertReaction: widget.dependencies.upsertBoardReaction,
                deleteReaction: widget.dependencies.deleteBoardReaction,
                fetchRatings: widget.dependencies.fetchBoardRatings,
                upsertRating: widget.dependencies.upsertBoardRating,
                deleteRating: widget.dependencies.deleteBoardRating,
                onCompose: () {
                  _keys[2].currentState?.pushNamed(
                    AppRoutes.boardCompose,
                    arguments: BoardComposeRouteArgs(userId: uid),
                  );
                },
              ),
            ),
            // F16: Profile tab (contract tabs are Home/Bookings/Board/
            // Profile). The Guide lives on Home (guide card) + its own
            // named routes, not as a tab.
            _TabNavigator(
              navigatorKey: _keys[3],
              dependencies: widget.dependencies,
              root: ProfileScreen(auth: widget.dependencies.auth),
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
              label: 'Bookings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.forum_outlined),
              label: 'Board',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outlined),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab's nested [Navigator]. The tab root renders directly; deeper pushes
/// resolve through the central [AppRoutes.onGenerateRoute] table WITH the
/// shell's [dependencies] (F19 fix: without them, in-tab pushes of
/// dependency-backed routes like login/history land on the "App dependencies
/// missing" error screen). Unknown names land on the shared error screen,
/// which always has a pop path.
class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;
  final AppDependencies dependencies;

  const _TabNavigator({
    required this.navigatorKey,
    required this.root,
    required this.dependencies,
  });

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == Navigator.defaultRouteName) {
          return MaterialPageRoute<void>(builder: (_) => root);
        }
        return AppRoutes.onGenerateRoute(settings, dependencies: dependencies);
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
