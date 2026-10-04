import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../auth/auth_repository.dart' show AuthUser;
import '../auth/auth_state.dart';
import 'home/home_display_name.dart';
import 'home/home_greeting.dart';
import 'home/home_sections.dart';
import 'home/popular_routes_catalog.dart';
import 'home/recent_searches_store.dart';
import 'home/upcoming_booking.dart';
import 'models/station.dart';
import 'search_date_utils.dart';
import 'search_state.dart';

/// Demo-horizon limit from `09_HOME_SEARCH_SPEC.md`: the hosted demo
/// timetable is generated for today..today+20 days, so the picker stops there
/// (server-side enforcement lives in `refresh_demo_horizon`).
const int kDemoBookingHorizonDays = 20;

/// Last selectable journey date for the current local day.
DateTime demoHorizonLastDate([DateTime? now]) {
  final DateTime clock = now ?? DateTime.now();
  return dayStartOf(clock).add(const Duration(days: kDemoBookingHorizonDays));
}

/// Home/search screen: dynamic greeting header, From/To card with an animated
/// swap, journey date with a chip strip, Search Trains button and the Home
/// content sections (upcoming booking, popular demo routes, recent searches,
/// Station Guide promo, demo-data notice).
///
/// Wiring (host owns composition, this screen owns no backend):
/// * [state] — the shared `SearchState` (station catalog + form + results).
///   The station catalog is loaded once on first mount when it is still empty.
/// * [auth] — optional `AuthState`; when supplied the header greets the
///   signed-in account by display name, otherwise the neutral greeting shows.
/// * [recentSearches] — injectable local history store (defaults to an
///   in-memory session store; pass `SharedPreferencesRecentSearchStore` for
///   on-device persistence).
/// * [loadUpcomingBooking] — optional seam for the traveller's next booking.
///   Leave it null (the current default) and the section renders its honest
///   empty state — nothing is fabricated.
class HomeSearchScreen extends StatefulWidget {
  final SearchState state;
  final VoidCallback? onSearchSubmitted;
  final VoidCallback? onStationGuideTap;

  /// Optional session source for the greeting + upcoming-booking sign-in copy.
  final AuthState? auth;

  /// Optional local recent-search store.
  final RecentSearchStore? recentSearches;

  /// Optional seam returning the traveller's next upcoming booking (null when
  /// there is none). See `home/upcoming_booking.dart` for exact wiring.
  final LoadUpcomingBooking? loadUpcomingBooking;

  /// Opens the traveller's booking details/ticket.
  final VoidCallback? onViewBooking;

  /// Opens sign-in (shown by the upcoming-booking section while signed out).
  final VoidCallback? onSignIn;

  final DateTime Function()? clock;

  const HomeSearchScreen({
    super.key,
    required this.state,
    this.onSearchSubmitted,
    this.onStationGuideTap,
    this.auth,
    this.recentSearches,
    this.loadUpcomingBooking,
    this.onViewBooking,
    this.onSignIn,
    this.clock,
  });

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  late final RecentSearchesController _recent = RecentSearchesController(
    store: widget.recentSearches ?? InMemoryRecentSearchStore(),
  );

  @override
  void initState() {
    super.initState();
    _recent.load();
    // The station catalog powers both the From/To pickers and the popular
    // route shortcuts; load it once when it has not been loaded yet.
    if (widget.state.stations.isEmpty &&
        widget.state.status == SearchStatus.idle) {
      widget.state.loadStations();
    }
  }

  @override
  void dispose() {
    _recent.dispose();
    super.dispose();
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  AuthUser? get _user => widget.auth?.user;

  bool get _signedIn => _user != null;

  void _swapEndpoints() {
    widget.state.swapEndpoints();
  }

  void _openStationGuide(BuildContext context) {
    if (widget.onStationGuideTap != null) {
      widget.onStationGuideTap!();
      return;
    }
    try {
      Navigator.pushNamed(context, 'station-guide');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station Guide is coming in I01.')),
      );
    }
  }

  Future<void> _submit(BuildContext context) async {
    if (dayStartOf(widget.state.selectedDate)
        .isAfter(demoHorizonLastDate(_now))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Demo schedules are available for the next '
            '$kDemoBookingHorizonDays days.',
          ),
        ),
      );
      return;
    }
    await widget.state.search();
    if (!context.mounted) return;
    if (widget.state.status == SearchStatus.loaded) {
      await _recordRecentSearch();
      widget.onSearchSubmitted?.call();
    } else if (widget.state.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.state.errorMessage!)));
    }
  }

  /// Recent searches come only from a search the traveller actually ran.
  Future<void> _recordRecentSearch() async {
    final Station? origin = widget.state.origin;
    final Station? destination = widget.state.destination;
    if (origin == null || destination == null) return;
    await _recent.record(
      RecentSearch(
        originId: origin.id,
        destinationId: destination.id,
        originLabel: origin.name,
        destinationLabel: destination.name,
        date: widget.state.selectedDate,
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime today = dayStartOf(_now);
    final DateTime last = demoHorizonLastDate(_now);
    final DateTime current = widget.state.selectedDate;
    final DateTime initial = current.isBefore(today)
        ? today
        : (current.isAfter(last) ? today : current);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
    );
    if (picked != null) widget.state.selectDate(picked);
  }

  void _applyPopularRoute(ResolvedPopularRoute route) {
    widget.state.selectOrigin(route.origin);
    widget.state.selectDestination(route.destination);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${route.label} selected. Choose a date and search.'),
      ),
    );
  }

  void _restoreRecent(RecentSearch entry) {
    final List<Station> stations = widget.state.stations;
    Station? byId(String id) {
      for (final Station station in stations) {
        if (station.id == id) return station;
      }
      return null;
    }

    final Station? origin = byId(entry.originId);
    final Station? destination = byId(entry.destinationId);
    if (origin == null || destination == null) {
      // Honest: never restore a route the live catalog cannot resolve.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That station is not in the current catalogue.'),
        ),
      );
      return;
    }
    widget.state.selectOrigin(origin);
    widget.state.selectDestination(destination);
    final DateTime last = demoHorizonLastDate(_now);
    widget.state.selectDate(
      entry.date.isAfter(last) ? dayStartOf(_now) : entry.date,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthState? auth = widget.auth;
    final List<Listenable> listenables = <Listenable>[
      widget.state,
      _recent,
      ?auth,
    ];
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (BuildContext context, _) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FadeSlideIn(
                  child: HomeGreetingHeader(
                    displayName: homeDisplayName(_user),
                    now: _now,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.s12,
                    AppSpacing.page,
                    AppSpacing.s24,
                  ),
                  child: StaggeredColumn(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildRouteCard(context),
                      const SizedBox(height: AppSpacing.s12),
                      _buildDateCard(context),
                      const SizedBox(height: AppSpacing.s12),
                      _buildSearchButton(context),
                      const SizedBox(height: AppSpacing.s24),
                      UpcomingBookingSection(
                        signedIn: _signedIn,
                        loader: widget.loadUpcomingBooking,
                        onViewBooking: widget.onViewBooking,
                        onSignIn: widget.onSignIn,
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      PopularRoutesSection(
                        stations: widget.state.stations,
                        onSelect: _applyPopularRoute,
                        onRetry: () => widget.state.loadStations(),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      RecentSearchesSection(
                        controller: _recent,
                        stations: widget.state.stations,
                        onRestore: _restoreRecent,
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      _buildStationGuideCard(context),
                      const SizedBox(height: AppSpacing.s8),
                      const HomeDemoNotice(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRouteCard(BuildContext context) {
    return HomeSectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              children: <Widget>[
                // Keyed by station so picking another endpoint cross-fades
                // the field instead of popping it.
                AnimatedSwap(
                  child: _StationField(
                    key: ValueKey<String>(
                      'from_${widget.state.origin?.id ?? 'none'}',
                    ),
                    label: 'From',
                    icon: Icons.trip_origin,
                    value: widget.state.origin,
                    stations: widget.state.stations,
                    hint: 'Select origin',
                    onChanged: widget.state.selectOrigin,
                  ),
                ),
                const Divider(height: AppSpacing.s24),
                AnimatedSwap(
                  child: _StationField(
                    key: ValueKey<String>(
                      'to_${widget.state.destination?.id ?? 'none'}',
                    ),
                    label: 'To',
                    icon: Icons.location_on_outlined,
                    value: widget.state.destination,
                    stations: widget.state.stations,
                    hint: 'Select destination',
                    onChanged: widget.state.selectDestination,
                  ),
                ),
              ],
            ),
          ),
          _SwapEndpointsButton(onSwap: _swapEndpoints),
        ],
      ),
    );
  }

  Widget _buildDateCard(BuildContext context) {
    final DateTime today = dayStartOf(_now);
    final DateTime last = demoHorizonLastDate(_now);
    final List<DateTime> chips = <DateTime>[
      for (final DateTime day in dateStrip(widget.state.selectedDate))
        if (!day.isBefore(today)) day,
    ];
    return HomeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PressScale(
            onTap: () => _pickDate(context),
            semanticsLabel: 'Choose journey date',
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.s12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Journey date', style: AppTypography.metadata),
                    Text(
                      formatJourneyDate(widget.state.selectedDate),
                      style: AppTypography.cardTitle,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Up to ${formatShortDate(last)}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final DateTime day in chips)
                _DateChip(
                  date: day,
                  selected:
                      dayStartOf(day) == dayStartOf(widget.state.selectedDate),
                  onTap: day.isAfter(last)
                      ? null
                      : () => widget.state.selectDate(day),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchButton(BuildContext context) {
    final bool loading = widget.state.isLoading;
    // Keyed by state so idle <-> searching cross-fades instead of popping.
    return AnimatedSwap(
      child: FilledButton.icon(
        key: ValueKey<bool>(loading),
        onPressed: loading ? null : () => _submit(context),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.search),
        label: Text(loading ? 'Searching…' : 'Search Trains'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle: AppTypography.button,
        ),
      ),
    );
  }

  Widget _buildStationGuideCard(BuildContext context) {
    return HomeSectionCard(
      onTap: () => _openStationGuide(context),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.maps_home_work_outlined,
            color: AppColors.success,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Station Guide', style: AppTypography.cardTitle),
                Text(
                  'Explore railway stations with maps, photos and helpful info.',
                  style: AppTypography.metadata,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Swap control: rotates 180° on tap (motion matrix "Swap route"). Under
/// reduced motion the rotation is instant and the icon still changes, so the
/// state stays clear.
class _SwapEndpointsButton extends StatefulWidget {
  final VoidCallback onSwap;

  const _SwapEndpointsButton({required this.onSwap});

  @override
  State<_SwapEndpointsButton> createState() => _SwapEndpointsButtonState();
}

class _SwapEndpointsButtonState extends State<_SwapEndpointsButton> {
  bool _halfTurn = false;

  void _swap() {
    setState(() => _halfTurn = !_halfTurn);
    // The route swap starts immediately; the rotation is pure feedback and
    // never postpones the action.
    widget.onSwap();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return IconButton.filledTonal(
      onPressed: _swap,
      tooltip: 'Swap origin and destination',
      icon: AnimatedRotation(
        turns: _halfTurn ? 0.5 : 0.0,
        duration: AppMotion.resolve(AppMotion.standard, reduced: reduced),
        child: const Icon(Icons.swap_vert),
      ),
    );
  }
}

class _StationField extends StatelessWidget {
  final String label;
  final IconData icon;
  final Station? value;
  final List<Station> stations;
  final String hint;
  final ValueChanged<Station?> onChanged;

  const _StationField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.stations,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: DropdownButtonFormField<Station>(
            key: ValueKey<String>('station_${label}_${value?.id}'),
            initialValue: value,
            hint: Text(hint),
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(borderRadius: AppRadii.inputRadius),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s8,
              ),
            ),
            items: <DropdownMenuItem<Station>>[
              for (final Station station in stations)
                DropdownMenuItem<Station>(
                  value: station,
                  child: Text(
                    '${station.name} (${station.code})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Date chip: colour + scale transition on selection (matrix "Date chip").
/// Disabled (beyond the demo horizon) chips never animate as tappable.
class _DateChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback? onTap;

  const _DateChip({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const List<String> weekdays = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    final bool enabled = onTap != null;
    final bool reduced = ReducedMotion.isReduced(context);
    return AnimatedScale(
      scale: selected ? 1.04 : 1.0,
      duration: AppMotion.resolve(AppMotion.fast, reduced: reduced),
      curve: AppMotion.enter,
      child: AnimatedContainer(
        duration: AppMotion.resolve(AppMotion.fast, reduced: reduced),
        curve: AppMotion.enter,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.pageBackground,
          borderRadius: AppRadii.chipRadius,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Semantics(
          button: enabled,
          selected: selected,
          label: 'Journey date ${formatJourneyDate(date)}',
          child: InkWell(
            borderRadius: AppRadii.chipRadius,
            onTap: onTap,
            child: Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Column(
                children: <Widget>[
                  Text(
                    date.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selected
                          ? AppColors.onPrimary
                          : AppColors.primaryText,
                    ),
                  ),
                  Text(
                    weekdays[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? Colors.white70
                          : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
