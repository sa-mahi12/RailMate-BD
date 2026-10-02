/// P10 — popular demo route shortcuts for the Home tab (V4
/// `09_HOME_SEARCH_SPEC.md`: 5–8 shortcuts, tap pre-fills From/To, clearly
/// part of the demo catalog).
///
/// HONESTY CONTRACT: [kDemoPopularRoutes] holds only origin/destination
/// station CODES that exist in the hosted `public.stations` catalog, taken
/// from the APPLIED demo-horizon service list
/// (`supabase/migrations/20260928000001_demo_horizon.sql` §4). No station id,
/// name, fare or schedule is hardcoded here. Every card is resolved against the
/// LIVE station list that [SearchState] loads
/// (`SearchApi.fetchStations` / GraphQL `stationsCollection`), so a code that
/// is not in the database simply does not render — the section can never show
/// an invented route.
library;

import '../models/station.dart';

/// One demo route shortcut: a station-code pair plus the demo service that runs
/// it in the applied demo horizon.
class DemoPopularRoute {
  final String originCode;
  final String destinationCode;
  final String serviceLabel;

  const DemoPopularRoute({
    required this.originCode,
    required this.destinationCode,
    required this.serviceLabel,
  });

  @override
  String toString() => 'DemoPopularRoute($originCode->$destinationCode)';
}

/// Six applied demo-corridor shortcuts (5–8 per spec).
///
/// Codes: DAC/CGP/SYL/RJH/KHL — all applied by migration
/// `20260928000001_demo_horizon.sql` §1 and stable there.
const List<DemoPopularRoute> kDemoPopularRoutes = <DemoPopularRoute>[
  DemoPopularRoute(
    originCode: 'DAC',
    destinationCode: 'CGP',
    serviceLabel: 'Subarna Express (Demo)',
  ),
  DemoPopularRoute(
    originCode: 'CGP',
    destinationCode: 'DAC',
    serviceLabel: 'Subarna Express (Demo)',
  ),
  DemoPopularRoute(
    originCode: 'DAC',
    destinationCode: 'SYL',
    serviceLabel: 'Parabat Express (Demo)',
  ),
  DemoPopularRoute(
    originCode: 'SYL',
    destinationCode: 'DAC',
    serviceLabel: 'Upaban Express (Demo)',
  ),
  DemoPopularRoute(
    originCode: 'DAC',
    destinationCode: 'RJH',
    serviceLabel: 'Silkcity Express (Demo)',
  ),
  DemoPopularRoute(
    originCode: 'DAC',
    destinationCode: 'KHL',
    serviceLabel: 'Sundarban Express (Demo)',
  ),
];

/// A [DemoPopularRoute] resolved against the live station catalog.
class ResolvedPopularRoute {
  final DemoPopularRoute route;
  final Station origin;
  final Station destination;

  const ResolvedPopularRoute({
    required this.route,
    required this.origin,
    required this.destination,
  });

  /// `DAC → CGP` label.
  String get label => '${origin.code} → ${destination.code}';
}

/// Resolves [catalog] against the live [stations] list.
///
/// Unresolvable pairs (station not in the database) are dropped rather than
/// rendered — the UI therefore cannot show a route the backend does not know.
/// Comparison is case-insensitive on [Station.code].
List<ResolvedPopularRoute> resolvePopularRoutes(
  List<Station> stations, {
  List<DemoPopularRoute> catalog = kDemoPopularRoutes,
}) {
  final Map<String, Station> byCode = <String, Station>{
    for (final Station s in stations) s.code.trim().toUpperCase(): s,
  };
  final List<ResolvedPopularRoute> out = <ResolvedPopularRoute>[];
  for (final DemoPopularRoute route in catalog) {
    final Station? origin = byCode[route.originCode.toUpperCase()];
    final Station? destination = byCode[route.destinationCode.toUpperCase()];
    if (origin == null || destination == null) continue;
    out.add(
      ResolvedPopularRoute(
        route: route,
        origin: origin,
        destination: destination,
      ),
    );
  }
  return out;
}
