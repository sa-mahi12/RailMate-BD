import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../design/design.dart';
import '../features/board/post/post.dart';
import '../features/board/post/post_feed_realtime.dart';
import '../features/board/post/post_feed_state.dart';
import '../features/board/post/feed_screen.dart';
import '../features/booking/passenger_ui/passenger.dart';
import '../features/booking/passenger_ui/passenger_form_state.dart';
import '../features/booking/payment_ui/payment_state.dart';
import '../features/booking/seat_ui/seat_selection_state.dart';
import '../features/bookings/booking_history.dart';
import '../features/bookings/booking_history_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/home/recent_searches_store.dart';
import '../features/search/home/upcoming_booking.dart';
import '../features/search/home_search_screen.dart';
import '../features/search/models/trip.dart';
import '../features/search/search_date_utils.dart';
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
  /// P10 seam: the next upcoming booking for the Home card.
  ///
  /// Returns `null` (which the card renders as its honest "no upcoming
  /// booking" empty state) until a trip-lookup seam exists. `BookingSummary`
  /// carries only `id`/`userId`/`tripId`/`status`/`totalFareBdt` — no origin,
  /// destination or departure time — and the search repository has no
  /// get-trip-by-id. Building a route card would mean inventing journey
  /// details, which this app never does.
  ///
  /// Next action (P13 follow-up): add `fetchTripById` to the search
  /// repository (plain REST read of an already-RLS-covered table) and map the
  /// resolved trip here.
  Future<UpcomingBooking?> _loadNextUpcomingBooking(String uid) async {
    try {
      final rows = await widget.dependencies.historyFor(uid).listOwned(uid);
      if (rows.any((BookingSummary b) => b.isActive)) {
        debugPrint(
          'P10: active booking found for $uid, but no trip lookup is wired yet; '
          'rendering the honest empty state.',
        );
      }
      return null;
    } catch (e) {
      debugPrint('P10: upcoming booking lookup failed: $e');
      return null;
    }
  }

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
                            // Captured before any await: the failure path
                            // below runs after awaits and must not touch a
                            // context across the gap.
                            final messenger = ScaffoldMessenger.of(nav.context);
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
                                    // Consumer gate: the trip model only
                                    // carries station UUIDs, so resolve them
                                    // to code + name here (never print a raw
                                    // id on a ticket) and format the
                                    // departure for humans (never ISO-8601).
                                    fromLabel:
                                        '${_searchState.stationCode(trip.originStationId)} · ${_searchState.stationName(trip.originStationId)}',
                                    toLabel:
                                        '${_searchState.stationCode(trip.destinationStationId)} · ${_searchState.stationName(trip.destinationStationId)}',
                                    departLabel:
                                        '${formatJourneyDate(trip.departureAt)} · ${formatTime12(trip.departureAt)}',
                                  ),
                                ),
                              );
                            } on BookingSubmitException catch (e) {
                              // Genuine failure: taken seats refresh from
                              // live inventory, then the user is back on
                              // the payment screen with a plain-language
                              // reason (already humanized by
                              // BookingSubmitException.message). No ticket
                              // is fabricated on any path, and no
                              // dead-end "setup" screen is shown.
                              if (e.code == 'SEAT_UNAVAILABLE') {
                                await seats.revalidate();
                              }
                              nav.pop();
                              messenger.showSnackBar(
                                SnackBar(content: Text(e.message)),
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
            _TabBodyEntrance(
              active: _index == 0,
              child: _TabNavigator(
                navigatorKey: _keys[0],
                dependencies: widget.dependencies,
                root: HomeSearchScreen(
                  state: _searchState,
                  // P10: real session for the personalised greeting, a
                  // device-persistent recent-search history, and the next
                  // upcoming booking read through the SAME repository the
                  // Bookings tab uses (no fabricated rows).
                  auth: widget.dependencies.auth,
                  recentSearches: SharedPreferencesRecentSearchStore(),
                  loadUpcomingBooking: uid == null
                      ? null
                      : () => _loadNextUpcomingBooking(uid),
                  onViewBooking: () =>
                      _keys[1].currentState?.pushNamed(AppRoutes.history),
                  onSignIn: uid == null
                      ? () => _keys[0].currentState?.pushNamed(AppRoutes.login)
                      : null,
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
            ),
            _TabBodyEntrance(
              active: _index == 1,
              child: _TabNavigator(
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
            ),
            _TabBodyEntrance(
              active: _index == 2,
              child: _TabNavigator(
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
                  // Comments seams: per-post threads fed by the production
                  // closures; signed-out readers (uid null) see rows
                  // read-only.
                  fetchComments: widget.dependencies.fetchComments,
                  addComment: widget.dependencies.addCommentRow,
                  deleteComment: widget.dependencies.deleteCommentRow,
                  onCompose: () {
                    _keys[2].currentState?.pushNamed(
                      AppRoutes.boardCompose,
                      arguments: BoardComposeRouteArgs(userId: uid),
                    );
                  },
                ),
              ),
            ),
            // F16: Profile tab (contract tabs are Home/Bookings/Board/
            // Profile). The Guide lives on Home (guide card) + its own
            // named routes, not as a tab.
            _TabBodyEntrance(
              active: _index == 3,
              child: _TabNavigator(
                navigatorKey: _keys[3],
                dependencies: widget.dependencies,
                root: ProfileScreen(auth: widget.dependencies.auth),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _AnimatedBottomNavBar(
          currentIndex: _index,
          onTap: _selectTab,
        ),
      ),
    );
  }
}

/// P09 — the four contract tabs with their unselected and selected icons.
///
/// Unselected icons are exactly the icons the V3 `BottomNavigationBar` used,
/// so the resting appearance is unchanged; the filled variants only appear for
/// the selected tab.
const List<_ShellTab> _shellTabs = <_ShellTab>[
  _ShellTab('Home', Icons.search, Icons.search),
  _ShellTab(
    'Bookings',
    Icons.confirmation_number_outlined,
    Icons.confirmation_number,
  ),
  _ShellTab('Board', Icons.forum_outlined, Icons.forum),
  _ShellTab('Profile', Icons.person_outline, Icons.person),
];

class _ShellTab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _ShellTab(this.label, this.icon, this.selectedIcon);
}

/// P09 — animated replacement for the plain `BottomNavigationBar`.
///
/// Selection feedback, matching `28_MOTION_COMPONENT_MATRIX.md`
/// (bottom nav icon select: scale 1.0 -> 1.12, 160 ms; reduced motion: colour
/// only):
///
/// * a teal selection indicator slides between slots (aligned tween, 220 ms),
/// * the selected icon crossfades outline -> filled and scales to 1.12,
/// * every tab is a [PressScale] (0.985 on press, 100 ms) so the tap fires
///   immediately and no animation ever postpones navigation.
///
/// Behaviour kept identical to the previous bar: fixed four items, the same
/// labels, teal selected / grey unselected colour, `onTap` routed to the
/// shell's `_selectTab` (including the re-tap-pops-to-root rule), and the same
/// screen-reader contract (one labelled, `selected`-exposed button per tab,
/// 56 px tall so touch targets stay at or above 48 logical px).
class _AnimatedBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AnimatedBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  /// Maps a tab index onto an [Alignment] x coordinate in `-1..1`.
  static double _alignmentFor(int index, int count) {
    if (count <= 1) return 0;
    return -1 + (index / (count - 1)) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Sliding selection indicator: an aligned tween rather than a
            // rebuild, so only the indicator's position animates.
            SizedBox(
              height: 3,
              child: AnimatedAlign(
                alignment: Alignment(
                  _alignmentFor(currentIndex, _shellTabs.length),
                  0,
                ),
                duration: reduced ? Duration.zero : AppMotion.standard,
                curve: AppMotion.emphasized,
                child: const SizedBox(
                  width: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppRadii.pill),
                      ),
                    ),
                    child: SizedBox(height: 3, width: 44),
                  ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                for (int i = 0; i < _shellTabs.length; i++)
                  _ShellTabButton(
                    tab: _shellTabs[i],
                    index: i,
                    selected: i == currentIndex,
                    onTap: onTap,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One bottom-navigation tab: semantic button, press-scale feedback and the
/// icon/label motion for its selection state.
class _ShellTabButton extends StatelessWidget {
  final _ShellTab tab;
  final int index;
  final bool selected;
  final ValueChanged<int> onTap;

  const _ShellTabButton({
    required this.tab,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    final Duration motion = reduced ? Duration.zero : AppMotion.fast;
    final Color color = selected ? AppColors.primary : AppColors.secondaryText;
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedScale(
          scale: selected ? 1.12 : 1.0,
          duration: motion,
          curve: AppMotion.enter,
          child: AnimatedSwitcher(
            duration: motion,
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Icon(
              selected ? tab.selectedIcon : tab.icon,
              key: ValueKey<String>('shell-tab-icon-$index-$selected'),
              size: 24,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          tab.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: PressScale(
          onTap: () => onTap(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              // The outer Semantics node already carries the tab label and
              // state; the visual text/icon are decorative duplicates.
              child: ExcludeSemantics(child: Center(child: content)),
            ),
          ),
        ),
      ),
    );
  }
}

/// P09 — tab-body entrance (matrix: tab content crossfade, 180 ms; instant
/// under reduced motion).
///
/// The shell keeps its [IndexedStack] so each tab's [Navigator] and inner
/// route stack survive a tab switch; wrapping the stack itself in an
/// [AnimatedSwitcher] is impossible because both copies of the tree would hold
/// the same per-tab `GlobalKey<NavigatorState>`. Instead every tab body fades
/// in through this wrapper when it is first shown.
///
/// The fade plays **once per tab** (it is not replayed on rebuilds or on every
/// later selection — the matrix forbids replaying hero motion), which keeps a
/// realtime Board feed from repainting a full-screen layer on every switch.
class _TabBodyEntrance extends StatefulWidget {
  final bool active;
  final Widget child;

  const _TabBodyEntrance({required this.active, required this.child});

  @override
  State<_TabBodyEntrance> createState() => _TabBodyEntranceState();
}

class _TabBodyEntranceState extends State<_TabBodyEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
  );

  bool _reduced = false;
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = ReducedMotion.isReduced(context);
    _playIfNeeded();
  }

  @override
  void didUpdateWidget(_TabBodyEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _playIfNeeded();
    }
  }

  void _playIfNeeded() {
    if (_reduced || _played || !widget.active) return;
    _played = true;
    // Start after the frame so the fade always begins from the hidden state
    // instead of flashing the already-visible first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _controller.value.clamp(0.0, 1.0),
          child: child,
        );
      },
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
