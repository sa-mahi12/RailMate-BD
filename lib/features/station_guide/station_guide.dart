/// Offline-first station guide model (B09 compliant slice).
///
/// Pure Dart: no Flutter, no Supabase, no network, no WebView, no external
/// URLs. Seeded from the 4 known demo stations (DAC/CGP/SYL/RJH — see
/// `supabase/seed/01_demo_stations.sql`). All text is demonstration data.
///
/// R-09 (YouTube embed), R-10 (Maps embed), R-15 (GSAP), R-16 (Sass) are
/// BLOCKED pending teacher approval for embedded web technologies, so this
/// file intentionally contains no embed URLs, no iframe markup and no web
/// dependencies. See `web-guide/index.html` placeholder comments for the
/// post-approval insertion points.
class StationGuide {
  /// Stable station code matching `public.stations.code` (e.g. `DAC`).
  final String stationCode;

  /// Display name matching the demo seed (e.g. `Dhaka`).
  final String stationName;

  /// Facility labels shown as fact chips (e.g. `Waiting Room`).
  final List<String> facilities;

  /// Public helpline text (demonstration value, not a real helpline).
  final String helpline;

  /// Short "how to reach" paragraph (demonstration directions).
  final String howToReach;

  const StationGuide({
    required this.stationCode,
    required this.stationName,
    required this.facilities,
    required this.helpline,
    required this.howToReach,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'stationCode': stationCode,
      'stationName': stationName,
      'facilities': List<String>.unmodifiable(facilities),
      'helpline': helpline,
      'howToReach': howToReach,
    };
  }

  factory StationGuide.fromMap(Map<String, dynamic> map) {
    final rawFacilities = map['facilities'];
    final List<String> facilities = rawFacilities is List
        ? rawFacilities.map((e) => e.toString()).toList()
        : const <String>[];
    return StationGuide(
      stationCode: map['stationCode'] as String,
      stationName: map['stationName'] as String,
      facilities: facilities,
      helpline: map['helpline'] as String,
      howToReach: map['howToReach'] as String,
    );
  }
}

/// Demonstration guide entries for the 4 seed stations. Offline-first:
/// callers render this list without any network call.
const List<StationGuide> demoStationGuides = <StationGuide>[
  StationGuide(
    stationCode: 'DAC',
    stationName: 'Dhaka',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Food Stalls'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach: 'Demo directions: central city station reachable by local bus and rickshaw. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'CGP',
    stationName: 'Chattogram',
    facilities: <String>['Waiting Room', 'Luggage Counter', 'Tea Stalls'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach: 'Demo directions: port-city station reachable by city bus and auto-rickshaw. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'SYL',
    stationName: 'Sylhet',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Restrooms'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach: 'Demo directions: north-east station reachable by town bus and rickshaw. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'RJH',
    stationName: 'Rajshahi',
    facilities: <String>['Waiting Room', 'Food Stalls', 'Restrooms'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach: 'Demo directions: western station reachable by city bus and rickshaw. DEMONSTRATION ONLY.',
  ),
];

/// Looks up a demo guide by station [code] (case-insensitive, trimmed).
///
/// Returns `null` for unknown/blank codes instead of throwing, so list and
/// detail screens can render the empty state.
StationGuide? findGuideByCode(String code) {
  final String needle = code.trim().toUpperCase();
  if (needle.isEmpty) return null;
  for (final StationGuide guide in demoStationGuides) {
    if (guide.stationCode.toUpperCase() == needle) return guide;
  }
  return null;
}
