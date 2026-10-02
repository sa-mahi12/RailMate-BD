/// P10 - Home content section widgets (V4 `09_HOME_SEARCH_SPEC.md`,
/// `15_LOADING_EMPTY_ERROR_SUCCESS_SPEC.md`, motion matrix rows "Home cards",
/// "Popular route", "Upcoming booking").
///
/// Every section:
/// * wraps its content in the P01 motion primitives (`StaggeredColumn`,
///   `FadeSlideIn`, `PressScale`, `AnimatedSwap`, `SkeletonBlock`) which
///   already branch on `ReducedMotion`;
/// * renders an HONEST state - loading skeleton, empty card, failure card or
///   real data. No section invents a station, route, booking or price.
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../models/station.dart';
import '../search_date_utils.dart';
import 'popular_routes_catalog.dart';
import 'recent_searches_store.dart';
import 'upcoming_booking.dart';

/// Arrow glyph used on route labels (kept in one place so sections agree).
const String kRouteArrow = ' \u2192 ';

/// White card used by every Home section (design system: cards 16 radius,
/// low-opacity cool shadow).
class HomeSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const HomeSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        boxShadow: AppElevation.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : HomePressableCard(onTap: onTap!, child: content),
    );
  }
}

/// Card tap target with the motion matrix's press feedback (scale 0.985,
/// 100 ms, skipped under reduced motion).
///
/// Built on [InkWell] rather than a bare [GestureDetector] so ripple + press
/// highlight + Material semantics keep working and existing widget tests that
/// target the card's `InkWell` ancestor stay valid. The tap fires immediately;
/// the scale never postpones it.
class HomePressableCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius? borderRadius;

  const HomePressableCard({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
  });

  @override
  State<HomePressableCard> createState() => _HomePressableCardState();
}

class _HomePressableCardState extends State<HomePressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool reduced = ReducedMotion.isReduced(context);
    return InkWell(
      borderRadius: widget.borderRadius,
      onTap: widget.onTap,
      onHighlightChanged: reduced
          ? null
          : (bool value) {
              if (mounted && _pressed != value) {
                setState(() => _pressed = value);
              }
            },
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressScale : 1.0,
        duration: AppMotion.resolve(AppMotion.press, reduced: reduced),
        curve: AppMotion.enter,
        child: widget.child,
      ),
    );
  }
}

/// Section heading row: title on the left, optional trailing action.
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const HomeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: AppTypography.sectionTitle),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AppSpacing.s4),
                Text(subtitle!, style: AppTypography.caption),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AppSpacing.s8),
          trailing!,
        ],
      ],
    );
  }
}

/// Honest empty/error/state block: icon, title, one-line explanation and an
/// optional next action (pack 15).
class HomeEmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const HomeEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return HomeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTypography.cardTitle),
                    const SizedBox(height: AppSpacing.s4),
                    Text(message, style: AppTypography.metadata),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s12),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Fixed-size skeleton so Home sections never jump when data lands.
class HomeSectionSkeleton extends StatelessWidget {
  final double height;

  const HomeSectionSkeleton({super.key, this.height = 84});

  @override
  Widget build(BuildContext context) {
    return HomeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SkeletonBlock(width: 140, height: 16),
          const SizedBox(height: AppSpacing.s12),
          SkeletonBlock(height: height - 40, borderRadius: AppRadii.chip),
        ],
      ),
    );
  }
}

/// Demo-data disclaimer action (pack 09 "Demo-data info").
///
/// The exact pack copy is shown verbatim; nothing here claims real railway
/// data.
class HomeDemoNotice extends StatelessWidget {
  /// Pack copy - keep in sync with `09_HOME_SEARCH_SPEC.md`.
  static const String disclosure =
      'Schedules, fares and seat occupancy shown in RailMate BD are '
      'demonstration data.';

  /// Ticket-level copy shared with the booking slice.
  static const String ticketDisclaimer =
      'Demonstration ticket \u2014 not valid for travel';

  const HomeDemoNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PressScale(
        onTap: () => _showDialog(context),
        semanticsLabel: 'Demo data information',
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.secondaryText,
              ),
              const SizedBox(width: AppSpacing.s8),
              Flexible(
                child: Text(
                  'About the demo data',
                  style: AppTypography.metadata.copyWith(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Demonstration data'),
          content: Text(disclosure, style: AppTypography.body),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }
}

/// Popular demo route shortcuts (tap pre-fills From/To).
///
/// When the live station catalog has not loaded (or failed), this renders the
/// honest unavailable state with a retry action instead of route cards.
class PopularRoutesSection extends StatelessWidget {
  final List<Station> stations;
  final ValueChanged<ResolvedPopularRoute> onSelect;
  final VoidCallback? onRetry;

  const PopularRoutesSection({
    super.key,
    required this.stations,
    required this.onSelect,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final List<ResolvedPopularRoute> routes = resolvePopularRoutes(stations);
    if (routes.isEmpty) {
      return HomeEmptyStateCard(
        icon: Icons.route_outlined,
        title: 'Popular demo routes',
        message:
            'Route shortcuts appear once the station catalogue loads. '
            'Nothing is shown from a cached list.',
        action: onRetry == null
            ? null
            : TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const HomeSectionHeader(
          title: 'Popular demo routes',
          subtitle: 'Shortcuts from the RailMate BD demonstration catalogue.',
        ),
        const SizedBox(height: AppSpacing.s12),
        // Wrap (not a nested scroll view): Home keeps exactly one Scrollable so
        // shell-level scroll helpers and accessibility traversal stay simple.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = AppSpacing.s12;
            final double width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (int index = 0; index < routes.length; index++)
                  FadeSlideIn(
                    key: ValueKey<String>(
                      'popular_route_${routes[index].label}',
                    ),
                    delay: AppMotion.staggerStep * index,
                    duration: AppMotion.standard,
                    child: SizedBox(
                      width: width,
                      child: _PopularRouteCard(
                        route: routes[index],
                        onTap: () => onSelect(routes[index]),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PopularRouteCard extends StatelessWidget {
  final ResolvedPopularRoute route;
  final VoidCallback onTap;

  const _PopularRouteCard({required this.route, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Select ${route.origin.name} to ${route.destination.name}',
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: AppElevation.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.train, size: 18, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      route.label,
                      style: AppTypography.cardTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text(
                '${route.origin.name}$kRouteArrow${route.destination.name}',
                style: AppTypography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                route.route.serviceLabel,
                style: AppTypography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Local recent searches: newest first, tap restores route + date.
class RecentSearchesSection extends StatelessWidget {
  final RecentSearchesController controller;
  final List<Station> stations;
  final ValueChanged<RecentSearch> onRestore;

  const RecentSearchesSection({
    super.key,
    required this.controller,
    required this.stations,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.isLoaded) {
      return const HomeSectionSkeleton(height: 72);
    }
    if (controller.entries.isEmpty) {
      return const HomeEmptyStateCard(
        icon: Icons.history,
        title: 'No recent searches',
        message:
            'Routes you actually search appear here so you can jump back in '
            'one tap. Nothing is pre-filled for you.',
      );
    }
    return HomeSectionCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          HomeSectionHeader(
            title: 'Recent searches',
            trailing: TextButton(
              onPressed: controller.clear,
              child: const Text('Clear all'),
            ),
          ),
          for (final RecentSearch entry in controller.entries)
            _RecentSearchRow(
              entry: entry,
              stations: stations,
              onTap: () => onRestore(entry),
            ),
        ],
      ),
    );
  }
}

class _RecentSearchRow extends StatelessWidget {
  final RecentSearch entry;
  final List<Station> stations;
  final VoidCallback onTap;

  const _RecentSearchRow({
    required this.entry,
    required this.stations,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String origin = entry.labelFor(
      entry.originId,
      entry.originLabel,
      stations,
    );
    final String destination = entry.labelFor(
      entry.destinationId,
      entry.destinationLabel,
      stations,
    );
    return Semantics(
      button: true,
      label: 'Restore search from $origin to $destination',
      child: PressScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.history,
                size: 20,
                color: AppColors.secondaryText,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$origin$kRouteArrow$destination',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      formatShortDate(entry.date),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.north_east,
                size: 16,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Upcoming booking card - real booking only.
class UpcomingBookingSection extends StatefulWidget {
  final bool signedIn;

  /// Pre-resolved booking (host may supply it directly instead of a loader).
  final UpcomingBooking? booking;

  /// Optional async loader seam; see `upcoming_booking.dart` for wiring.
  final LoadUpcomingBooking? loader;

  final VoidCallback? onViewBooking;
  final VoidCallback? onFindTrain;
  final VoidCallback? onSignIn;
  final VoidCallback? onRetry;

  const UpcomingBookingSection({
    super.key,
    required this.signedIn,
    this.booking,
    this.loader,
    this.onViewBooking,
    this.onFindTrain,
    this.onSignIn,
    this.onRetry,
  });

  @override
  State<UpcomingBookingSection> createState() => _UpcomingBookingSectionState();
}

enum _UpcomingState { loading, ready, none, failed }

class _UpcomingBookingSectionState extends State<UpcomingBookingSection> {
  _UpcomingState _state = _UpcomingState.loading;
  UpcomingBooking? _booking;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    if (_booking != null) {
      _state = _UpcomingState.ready;
    } else if (widget.signedIn && widget.loader != null) {
      _load(fromInit: true);
    } else {
      _state = _UpcomingState.none;
    }
  }

  @override
  void didUpdateWidget(UpcomingBookingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.booking != null && widget.booking != oldWidget.booking) {
      setState(() {
        _booking = widget.booking;
        _state = _UpcomingState.ready;
      });
      return;
    }
    final bool becameSignedIn = !oldWidget.signedIn && widget.signedIn;
    if (becameSignedIn && widget.loader != null && _booking == null) {
      _load(fromInit: true);
    }
  }

  /// Reads the injected loader. [fromInit] skips `setState` so the first read
  /// (issued from `initState`) never marks the element dirty mid-build.
  Future<void> _load({bool fromInit = false}) async {
    final LoadUpcomingBooking? loader = widget.loader;
    if (loader == null) return;
    if (fromInit) {
      _state = _UpcomingState.loading;
    } else {
      setState(() => _state = _UpcomingState.loading);
    }
    try {
      final UpcomingBooking? booking = await loader();
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _state = booking == null ? _UpcomingState.none : _UpcomingState.ready;
      });
    } catch (_) {
      // Honest failure: a load error is never reported as "no bookings".
      if (!mounted) return;
      setState(() => _state = _UpcomingState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _UpcomingState.loading:
        return const HomeSectionSkeleton(height: 96);
      case _UpcomingState.failed:
        return HomeEmptyStateCard(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your bookings',
          message:
              'The booking list could not be read. No booking was created or '
              'changed.',
          action: widget.loader == null
              ? null
              : OutlinedButton(
                  onPressed: () => _load(),
                  child: const Text('Retry'),
                ),
        );
      case _UpcomingState.none:
        return widget.signedIn
            ? HomeEmptyStateCard(
                icon: Icons.confirmation_number_outlined,
                title: 'No upcoming bookings',
                message:
                    'Search for a journey \u2014 confirmed demo tickets appear '
                    'here.',
                action: _findTrainAction,
              )
            : HomeEmptyStateCard(
                icon: Icons.account_circle_outlined,
                title: 'Sign in to see your tickets',
                message:
                    'Upcoming demo tickets are tied to your account. You can '
                    'still search journeys without signing in.',
                action: widget.onSignIn == null
                    ? null
                    : OutlinedButton(
                        onPressed: widget.onSignIn,
                        child: const Text('Sign in'),
                      ),
              );
      case _UpcomingState.ready:
        return _buildBooking(_booking!);
    }
  }

  Widget? get _findTrainAction => widget.onFindTrain == null
      ? null
      : OutlinedButton(
          onPressed: widget.onFindTrain,
          child: const Text('Find a train'),
        );

  Widget _buildBooking(UpcomingBooking booking) {
    final String time = formatTime12(booking.departureAt);
    final String day = formatShortDate(booking.departureAt);
    return HomeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HomeSectionHeader(title: 'Your next trip'),
          const SizedBox(height: AppSpacing.s12),
          // Crossfade (matrix: "upcoming booking crossfade").
          AnimatedSwap(
            child: Column(
              key: ValueKey<String>('upcoming_${booking.reference}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.train, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        booking.routeLabel,
                        style: AppTypography.cardTitle,
                      ),
                    ),
                    Text(booking.reference, style: AppTypography.metadata),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  booking.serviceLabel,
                  style: AppTypography.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('$day \u00b7 $time', style: AppTypography.body),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Seats: ${booking.seatsLabel}',
                  style: AppTypography.caption,
                ),
                Text(
                  HomeDemoNotice.ticketDisclaimer,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger,
                  ),
                ),
                if (widget.onViewBooking != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.s12),
                  FilledButton(
                    onPressed: widget.onViewBooking,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.buttonRadius,
                      ),
                    ),
                    child: const Text('View ticket / details'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
