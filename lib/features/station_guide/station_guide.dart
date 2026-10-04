/// P22 - offline-first station guide data (B09 slice, expanded by P22).
///
/// Pure Dart: no Flutter, no Supabase, no network, no WebView, no external
/// URLs. Every entry is **demonstration content**: facility labels, arrival
/// tips and directions written for this academic demo, not official railway
/// information, and no entry claims a live service, delay, helpline or fare.
///
/// Honesty rules applied by P22:
/// * `helpline` is nullable and **null for every entry** — no official
///   helpline is invented, so the UI omits the row instead of printing a
///   made-up number.
/// * `latitude`/`longitude` are the static seed coordinates that back the
///   bundled Leaflet page; entries without one declare `hasMapPage == false`
///   and the UI says so rather than pointing at another station's pin.
/// * The four original seed stations (DAC/CGP/SYL/RJH, see
///   `supabase/seed/01_demo_stations.sql`) are unchanged in
///   [demoStationGuides]; the expanded [stationGuideCatalog] keeps them as
///   its first four entries so existing callers and tests are unaffected.
library;

/// One offline guide entry.
///
/// Fields beyond the B09 slice (city/division/district, description, arrival
/// tip, coordinates) come from
/// `11_BOARD_GUIDE_PROFILE_SPEC.md`: station name/code, city/division/
/// district, short description, facilities, generic arrival/access tip,
/// coordinates, map.
class StationGuide {
  /// Stable station code matching `public.stations.code` (e.g. `DAC`).
  final String stationCode;

  /// Display name matching the demo seed (e.g. `Dhaka`).
  final String stationName;

  /// Facility labels shown as fact chips (e.g. `Waiting Room`).
  final List<String> facilities;

  /// Public helpline text. **Null in every demo entry**: no official
  /// helpline was verifiable, so none is printed.
  final String? helpline;

  /// Short "how to reach" paragraph (demonstration directions).
  final String howToReach;

  /// City / town the station serves (demonstration value).
  final String city;

  /// Division the station belongs to (demonstration value).
  final String division;

  /// District the station belongs to (demonstration value).
  final String district;

  /// One-line description shown under the station name.
  final String description;

  /// Generic arrival / access tip. Never a promise about a specific service.
  final String arrivalTip;

  /// Static demonstration latitude in decimal degrees, or null when the
  /// station is not part of the bundled map page.
  final double? latitude;

  /// Static demonstration longitude in decimal degrees, or null.
  final double? longitude;

  const StationGuide({
    required this.stationCode,
    required this.stationName,
    required this.facilities,
    required this.helpline,
    required this.howToReach,
    required this.city,
    required this.division,
    required this.district,
    required this.description,
    required this.arrivalTip,
    this.latitude,
    this.longitude,
  });

  /// True when the bundled interactive page has a pin for this station.
  bool get hasMapPage => latitude != null && longitude != null;

  /// Copy shared by every entry so no screen can accidentally drop it.
  static const String demonstrationNotice = 'DEMONSTRATION ONLY';

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'stationCode': stationCode,
      'stationName': stationName,
      'facilities': List<String>.unmodifiable(facilities),
      'helpline': helpline,
      'howToReach': howToReach,
      'city': city,
      'division': division,
      'district': district,
      'description': description,
      'arrivalTip': arrivalTip,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory StationGuide.fromMap(Map<String, dynamic> map) {
    final Object? rawFacilities = map['facilities'];
    final List<String> facilities = rawFacilities is List
        ? rawFacilities.map((Object? e) => e.toString()).toList()
        : const <String>[];
    final Object? rawHelpline = map['helpline'];
    return StationGuide(
      stationCode: map['stationCode'] as String,
      stationName: map['stationName'] as String,
      facilities: facilities,
      helpline: rawHelpline is String && rawHelpline.isNotEmpty
          ? rawHelpline
          : null,
      howToReach: (map['howToReach'] ?? '') as String,
      city: (map['city'] ?? '') as String,
      division: (map['division'] ?? '') as String,
      district: (map['district'] ?? '') as String,
      description: (map['description'] ?? '') as String,
      arrivalTip: (map['arrivalTip'] ?? '') as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }
}

/// The original four seeded demo stations (B09).
///
/// Kept verbatim (including their demonstration helpline wording) so the
/// B09 contract and its tests stay valid; [stationGuideCatalog] supersedes it
/// for the UI.
const List<StationGuide> demoStationGuides = <StationGuide>[
  StationGuide(
    stationCode: 'DAC',
    stationName: 'Dhaka',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Food Stalls'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach:
        'Demo directions: central city station reachable by local bus and '
        'rickshaw. DEMONSTRATION ONLY.',
    city: 'Dhaka',
    division: 'Dhaka',
    district: 'Dhaka',
    description: 'Largest demo hub used by the sample schedule.',
    arrivalTip:
        'Demo tip: arrive early and follow the posted platform signage. '
        'DEMONSTRATION ONLY.',
    latitude: 23.8103,
    longitude: 90.4125,
  ),
  StationGuide(
    stationCode: 'CGP',
    stationName: 'Chattogram',
    facilities: <String>['Waiting Room', 'Luggage Counter', 'Tea Stalls'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach:
        'Demo directions: port-city station reachable by city bus and '
        'auto-rickshaw. DEMONSTRATION ONLY.',
    city: 'Chattogram',
    division: 'Chattogram',
    district: 'Chattogram',
    description: 'Port-city demo station used by the sample schedule.',
    arrivalTip:
        'Demo tip: keep luggage with you on the concourse. '
        'DEMONSTRATION ONLY.',
    latitude: 22.3569,
    longitude: 91.7832,
  ),
  StationGuide(
    stationCode: 'SYL',
    stationName: 'Sylhet',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Restrooms'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach:
        'Demo directions: north-east station reachable by town bus and '
        'rickshaw. DEMONSTRATION ONLY.',
    city: 'Sylhet',
    division: 'Sylhet',
    district: 'Sylhet',
    description: 'North-east demo station used by the sample schedule.',
    arrivalTip:
        'Demo tip: the platform side is reached by a short covered walkway. '
        'DEMONSTRATION ONLY.',
    latitude: 24.8949,
    longitude: 91.8692,
  ),
  StationGuide(
    stationCode: 'RJH',
    stationName: 'Rajshahi',
    facilities: <String>['Waiting Room', 'Food Stalls', 'Restrooms'],
    helpline: 'Demo helpline 0000 (DEMONSTRATION ONLY)',
    howToReach:
        'Demo directions: western station reachable by city bus and '
        'rickshaw. DEMONSTRATION ONLY.',
    city: 'Rajshahi',
    division: 'Rajshahi',
    district: 'Rajshahi',
    description: 'Western demo station used by the sample schedule.',
    arrivalTip:
        'Demo tip: waiting hall seating is first come, first served. '
        'DEMONSTRATION ONLY.',
    latitude: 24.3745,
    longitude: 88.6042,
  ),
];

/// P22 - the expanded demo guide: twenty-four entries, all demonstration
/// content, one per live `public.stations` code (see P12).
///
/// The first four are the original seed stations ([demoStationGuides]);
/// [AIR]/[CML]/[FEN]/[KHL] also have a pin on the bundled map page, and
/// every other entry deliberately has **no** coordinates so the UI has to
/// be honest about the bundled map's coverage instead of pointing at
/// another station's pin.
///
/// Fixed in V4 P12 follow-up: the P22 draft codes `RNG`/`TKG` never existed
/// in `public.stations` (real codes are `RGP`/`TNG`) and `BSR` (Barishal)
/// has no backend station, so those three entries were corrected/replaced.
/// Every `stationCode` below now matches a live station code.
const List<StationGuide> stationGuideCatalog = <StationGuide>[
  ...demoStationGuides,
  StationGuide(
    stationCode: 'AIR',
    stationName: 'Dhaka Airport',
    facilities: <String>['Waiting Room', 'Luggage Counter', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: airport-area station reached by the airport road. '
        'DEMONSTRATION ONLY.',
    city: 'Dhaka',
    division: 'Dhaka',
    district: 'Dhaka',
    description: 'Demo entry for the airport-area halt.',
    arrivalTip:
        'Demo tip: allow extra time for the longer approach road. '
        'DEMONSTRATION ONLY.',
    latitude: 23.8431,
    longitude: 90.3973,
  ),
  StationGuide(
    stationCode: 'CML',
    stationName: 'Cumilla',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by local bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Cumilla',
    division: 'Chattogram',
    district: 'Cumilla',
    description: 'Demo entry on the Chattogram division list.',
    arrivalTip:
        'Demo tip: the ticket counter closes before the demo departure time. '
        'DEMONSTRATION ONLY.',
    latitude: 23.4607,
    longitude: 91.1809,
  ),
  StationGuide(
    stationCode: 'FEN',
    stationName: 'Feni',
    facilities: <String>['Waiting Room', 'Food Stalls'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Feni',
    division: 'Chattogram',
    district: 'Feni',
    description: 'Demo entry on the Chattogram division list.',
    arrivalTip:
        'Demo tip: keep to the marked waiting area while the demo train is '
        'on the platform. DEMONSTRATION ONLY.',
    latitude: 23.0235,
    longitude: 91.3841,
  ),
  StationGuide(
    stationCode: 'KHL',
    stationName: 'Khulna',
    facilities: <String>['Waiting Room', 'Luggage Counter', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by city bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Khulna',
    division: 'Khulna',
    district: 'Khulna',
    description: 'South-west demo entry.',
    arrivalTip:
        'Demo tip: the demo concourse is step-free on this platform. '
        'DEMONSTRATION ONLY.',
    latitude: 22.8456,
    longitude: 89.5403,
  ),
  StationGuide(
    stationCode: 'BOG',
    stationName: 'Bogura',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Food Stalls'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by city bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Bogura',
    division: 'Rajshahi',
    district: 'Bogura',
    description: 'Demo entry on the Rajshahi division list.',
    arrivalTip:
        'Demo tip: the platform changes are announced only inside the demo '
        'station building. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'CXB',
    stationName: 'Cox\'s Bazar',
    facilities: <String>['Waiting Room', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Cox\'s Bazar',
    division: 'Chattogram',
    district: 'Cox\'s Bazar',
    description: 'Demo entry for the coastal terminus.',
    arrivalTip:
        'Demo tip: the demo platform is reached through the main archway. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'RGP',
    stationName: 'Rangpur',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by city bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Rangpur',
    division: 'Rangpur',
    district: 'Rangpur',
    description: 'Northern demo entry.',
    arrivalTip:
        'Demo tip: cold-weather demo sessions start earlier. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'TNG',
    stationName: 'Tangail',
    facilities: <String>['Waiting Room', 'Food Stalls', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Tangail',
    division: 'Dhaka',
    district: 'Tangail',
    description: 'Central demo entry on the Dhaka division list.',
    arrivalTip:
        'Demo tip: the footbridge on this demo platform is stepped. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'JOY',
    stationName: 'Joydebpur',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by local bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Joydebpur',
    division: 'Dhaka',
    district: 'Gazipur',
    description: 'Demo entry on the Dhaka division list.',
    arrivalTip:
        'Demo tip: the demo platform is a short walk from the main gate. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'MYM',
    stationName: 'Mymensingh',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Food Stalls'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by city bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Mymensingh',
    division: 'Mymensingh',
    district: 'Mymensingh',
    description: 'Demo entry on the Mymensingh division list.',
    arrivalTip:
        'Demo tip: arrive early during the demo morning rush. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'JAM',
    stationName: 'Jamalpur',
    facilities: <String>['Waiting Room', 'Food Stalls'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Jamalpur',
    division: 'Mymensingh',
    district: 'Jamalpur',
    description: 'Demo entry on the Mymensingh division list.',
    arrivalTip:
        'Demo tip: the demo waiting hall fills up before evening trains. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'AKH',
    stationName: 'Akhaura',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by local bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Akhaura',
    division: 'Chattogram',
    district: 'Brahmanbaria',
    description: 'Demo entry on the Chattogram division list.',
    arrivalTip:
        'Demo tip: keep the demo ticket ready at the platform entry. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'BRA',
    stationName: 'Brahmanbaria',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Brahmanbaria',
    division: 'Chattogram',
    district: 'Brahmanbaria',
    description: 'Demo entry on the Chattogram division list.',
    arrivalTip:
        'Demo tip: the demo concourse is busiest around midday. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'SRM',
    stationName: 'Sreemangal',
    facilities: <String>['Waiting Room', 'Tea Stalls'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Sreemangal',
    division: 'Sylhet',
    district: 'Moulvibazar',
    description: 'Demo entry on the Sylhet division list.',
    arrivalTip:
        'Demo tip: the demo platform overlooks the tea-garden road. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'ISD',
    stationName: 'Ishwardi',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by local bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Ishwardi',
    division: 'Rajshahi',
    district: 'Pabna',
    description: 'Demo entry on the Rajshahi division list.',
    arrivalTip:
        'Demo tip: the demo junction has more than one platform — check '
        'the board. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'JSR',
    stationName: 'Jashore',
    facilities: <String>['Waiting Room', 'Food Stalls', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by city bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Jashore',
    division: 'Khulna',
    district: 'Jashore',
    description: 'Demo entry on the Khulna division list.',
    arrivalTip:
        'Demo tip: the demo waiting hall is past the ticket counters. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'SDP',
    stationName: 'Saidpur',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Saidpur',
    division: 'Rangpur',
    district: 'Nilphamari',
    description: 'Northern demo entry on the Rangpur division list.',
    arrivalTip:
        'Demo tip: cold-weather demo sessions start boarding earlier. '
        'DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'PBT',
    stationName: 'Parbatipur',
    facilities: <String>['Waiting Room', 'Food Stalls'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by local bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Parbatipur',
    division: 'Rangpur',
    district: 'Dinajpur',
    description: 'Northern demo entry on the Rangpur division list.',
    arrivalTip:
        'Demo tip: the demo junction connects several demo routes — '
        'confirm the train name. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'DIN',
    stationName: 'Dinajpur',
    facilities: <String>['Waiting Room', 'Ticket Counters', 'Restrooms'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by city bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Dinajpur',
    division: 'Rangpur',
    district: 'Dinajpur',
    description: 'Northern demo terminus on the Rangpur division list.',
    arrivalTip:
        'Demo tip: the demo terminus platform clears quickly after '
        'arrival. DEMONSTRATION ONLY.',
  ),
  StationGuide(
    stationCode: 'NOA',
    stationName: 'Noakhali',
    facilities: <String>['Waiting Room', 'Ticket Counters'],
    helpline: null,
    howToReach:
        'Demo directions: station reached by town bus and rickshaw. '
        'DEMONSTRATION ONLY.',
    city: 'Noakhali',
    division: 'Chattogram',
    district: 'Noakhali',
    description: 'Demo entry on the Chattogram division list.',
    arrivalTip:
        'Demo tip: the demo platform shelter covers the waiting area. '
        'DEMONSTRATION ONLY.',
  ),
];

/// Looks up a demo guide by station [code] (case-insensitive, trimmed).
///
/// Searches the expanded [stationGuideCatalog]. Returns `null` for
/// unknown/blank codes instead of throwing, so list and detail screens can
/// render the empty state.
StationGuide? findGuideByCode(String code) {
  final String needle = code.trim().toUpperCase();
  if (needle.isEmpty) return null;
  for (final StationGuide guide in stationGuideCatalog) {
    if (guide.stationCode.toUpperCase() == needle) return guide;
  }
  return null;
}

/// F15: bundled WebView asset path for the parameterized station guide page.
///
/// The file must be registered under `flutter/assets` in pubspec.yaml
/// (coordinator-owned) before the WebView can load it; until then
/// `GuideWebViewScreen` degrades to a genuine offline message.
const String guideAssetPath = 'web-guide/index.html';

/// F15: static demonstration coordinates (decimal degrees) backing the
/// Leaflet map in `web-guide/index.html`. Static seed values only — never
/// live GPS. Entries are `[latitude, longitude]`.
const Map<String, List<double>> stationCoordinates = <String, List<double>>{
  'DAC': <double>[23.8103, 90.4125],
  'CGP': <double>[22.3569, 91.7832],
  'SYL': <double>[24.8949, 91.8692],
  'RJH': <double>[24.3745, 88.6042],
  'AIR': <double>[23.8431, 90.3973],
  'CML': <double>[23.4607, 91.1809],
  'FEN': <double>[23.0235, 91.3841],
  'KHL': <double>[22.8456, 89.5403],
};

/// F15: default station code used when a requested code is unknown/blank.
const String defaultGuideStationCode = 'DAC';

/// Normalizes a raw station [code] to a known F15 map key.
///
/// Returns [defaultGuideStationCode] for unknown or blank input instead of
/// throwing, so the WebView always lands on a real demo station. Callers that
/// must not silently swap stations should check [hasGuideMapPage] first.
String normalizeGuideStationCode(String code) {
  final String needle = code.trim().toUpperCase();
  if (stationCoordinates.containsKey(needle)) return needle;
  return defaultGuideStationCode;
}

/// True when the bundled page really has a pin for [code].
///
/// Used by the detail screen so a station outside the bundled map is told so
/// honestly instead of being shown another station's marker.
bool hasGuideMapPage(String code) =>
    stationCoordinates.containsKey(code.trim().toUpperCase());

/// Builds the in-page query string selecting [code] on the bundled guide
/// page (e.g. `?station=CGP`). Unknown codes fall back to the default.
String guideStationQuery(String code) {
  return '?station=${normalizeGuideStationCode(code)}';
}
