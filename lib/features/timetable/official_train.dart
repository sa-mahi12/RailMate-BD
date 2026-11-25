/// P43 - official Bangladesh Railway timetable models.
///
/// Source of truth: the two published PDFs linked from
/// `https://railway.gov.bd/pages/static-pages/691997d5933eb65569ddf8e2`
/// (Timetable No. 54, effective 10 March 2025), transcribed row by row by
/// `tools/build_official_timetable.py` into
/// `assets/data/official-timetable.json`.
///
/// Honesty rules encoded here:
/// * the dataset is a *published timetable*, never live running status;
/// * only fields printed in the source are present - no platform, delay, ETA,
///   occupancy, fare or guessed intermediate stop;
/// * `overnightInferred` is arithmetic on two published times (an arrival at or
///   before the departure time can only be the next day), and the UI labels it
///   as inferred;
/// * `nameEn` is a transliteration of the published Bangla name, not an
///   official English name.
library;

/// Where one row came from: document, page and printed serial number.
class TimetableSource {
  /// Document key: `eastern` or `western`.
  final String document;

  /// 1-based page inside the PDF.
  final int page;

  /// Printed serial number inside that page's table.
  final int serial;

  const TimetableSource({
    required this.document,
    required this.page,
    required this.serial,
  });

  factory TimetableSource.fromJson(Map<String, dynamic> json) {
    return TimetableSource(
      document: _string(json, 'document'),
      page: _int(json, 'page'),
      serial: _int(json, 'serial'),
    );
  }
}

/// One published intermediate stop.
///
/// The current source summary tables publish only origin and destination, so
/// every train carries an empty list and an explicit [OfficialTrain.stopsNote].
/// The type exists so a future stop-level source can be added without a UI
/// rewrite.
class TrainStop {
  final String stationId;
  final String? arrival;
  final String? departure;

  const TrainStop({required this.stationId, this.arrival, this.departure});

  factory TrainStop.fromJson(Map<String, dynamic> json) {
    return TrainStop(
      stationId: _string(json, 'station'),
      arrival: _nullableString(json, 'arrival'),
      departure: _nullableString(json, 'departure'),
    );
  }
}

/// A station that appears in the official timetable.
///
/// Coordinates are deliberately absent: the timetable does not publish them,
/// so the directory says "not verified" instead of borrowing a pin from the
/// demonstration station guide.
class OfficialStation {
  final String id;
  final String nameBn;
  final String nameEn;
  final String nameProvenance;
  final List<String> zones;
  final double? latitude;
  final double? longitude;
  final String? coordinateProvenance;

  const OfficialStation({
    required this.id,
    required this.nameBn,
    required this.nameEn,
    required this.nameProvenance,
    required this.zones,
    this.latitude,
    this.longitude,
    this.coordinateProvenance,
  });

  bool get hasVerifiedCoordinates => latitude != null && longitude != null;

  factory OfficialStation.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? coordinates =
        json['coordinates'] as Map<String, dynamic>?;
    return OfficialStation(
      id: _string(json, 'id'),
      nameBn: _string(json, 'name_bn'),
      nameEn: _string(json, 'name_en'),
      nameProvenance: _string(json, 'name_provenance'),
      zones: _stringList(json, 'zones'),
      latitude: coordinates == null ? null : _double(coordinates, 'lat'),
      longitude: coordinates == null ? null : _double(coordinates, 'lng'),
      coordinateProvenance: _nullableString(json, 'coordinate_provenance'),
    );
  }
}

/// One published train direction.
class OfficialTrain {
  /// Stable dataset id, e.g. `e-ic-701-CTG-DAC`.
  final String id;
  final String zone;
  final String serviceClass;
  final String operationalStatus;
  final String trainNumber;
  final String? nameBn;
  final String? nameEn;
  final List<String> offDays;
  final String originStation;
  final String originDeparture;
  final String destinationStation;
  final String destinationArrival;
  final bool overnightInferred;
  final List<TrainStop> stops;
  final String stopsNote;
  final TimetableSource source;

  const OfficialTrain({
    required this.id,
    required this.zone,
    required this.serviceClass,
    required this.operationalStatus,
    required this.trainNumber,
    required this.nameBn,
    required this.nameEn,
    required this.offDays,
    required this.originStation,
    required this.originDeparture,
    required this.destinationStation,
    required this.destinationArrival,
    required this.overnightInferred,
    required this.stops,
    required this.stopsNote,
    required this.source,
  });

  /// True when the source prints this service as running today.
  ///
  /// The phased ("porjaye bastobayonjoggo") rows are published but not yet
  /// operational, so they are hidden from the default result list.
  bool get isPublished => operationalStatus == 'published';

  bool get isPhased => operationalStatus == 'phased';

  bool get isInternational => serviceClass == 'international';

  /// Human name: the transliterated English name when present, otherwise the
  /// published Bangla name, otherwise the number alone.
  String get displayName {
    final String? english = nameEn;
    if (english != null && english.isNotEmpty) {
      return english;
    }
    final String? bangla = nameBn;
    if (bangla != null && bangla.isNotEmpty) {
      return bangla;
    }
    return trainNumber;
  }

  int get departureMinutes => minutesOfDay(originDeparture);

  int get arrivalMinutes => minutesOfDay(destinationArrival);

  /// Published travel time in minutes, using the inferred day rollover.
  int get durationMinutes {
    final int raw = arrivalMinutes - departureMinutes;
    return overnightInferred ? raw + 24 * 60 : raw;
  }

  /// True when [weekday] (DateTime.monday .. DateTime.sunday) is the published
  /// weekly off day for this train.
  bool isOffOnWeekday(int weekday) {
    return offDays.contains(weekdayName(weekday));
  }

  factory OfficialTrain.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> origin = _map(json, 'origin');
    final Map<String, dynamic> destination = _map(json, 'destination');
    final List<dynamic> rawStops = _list(json, 'stops');
    return OfficialTrain(
      id: _string(json, 'id'),
      zone: _string(json, 'zone'),
      serviceClass: _string(json, 'service_class'),
      operationalStatus: _string(json, 'operational_status'),
      trainNumber: _string(json, 'train_number'),
      nameBn: _nullableString(json, 'name_bn'),
      nameEn: _nullableString(json, 'name_en'),
      offDays: _stringList(json, 'off_days'),
      originStation: _string(origin, 'station'),
      originDeparture: _time(origin, 'departure'),
      destinationStation: _string(destination, 'station'),
      destinationArrival: _time(destination, 'arrival'),
      overnightInferred: _bool(json, 'overnight_inferred'),
      stops: rawStops
          .map(
            (dynamic entry) =>
                TrainStop.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      stopsNote: _string(json, 'stops_note'),
      source: TimetableSource.fromJson(_map(json, 'source')),
    );
  }
}

/// The whole bundled dataset plus its provenance and coverage statement.
class OfficialDataset {
  final int schemaVersion;
  final String datasetId;
  final String timetableNumber;
  final String effectiveFrom;
  final String retrieved;
  final String lastVerified;
  final String notice;
  final String officialPortal;
  final bool intermediateStopsPublished;
  final List<String> importedSections;
  final List<String> coverageGaps;
  final int rowsTranscribed;
  final int rowsExcluded;
  final Map<String, String> documentUrls;
  final Map<String, String> documentHashes;
  final List<OfficialStation> stations;
  final List<OfficialTrain> trains;

  const OfficialDataset({
    required this.schemaVersion,
    required this.datasetId,
    required this.timetableNumber,
    required this.effectiveFrom,
    required this.retrieved,
    required this.lastVerified,
    required this.notice,
    required this.officialPortal,
    required this.intermediateStopsPublished,
    required this.importedSections,
    required this.coverageGaps,
    required this.rowsTranscribed,
    required this.rowsExcluded,
    required this.documentUrls,
    required this.documentHashes,
    required this.stations,
    required this.trains,
  });

  OfficialStation? stationById(String id) {
    for (final OfficialStation station in stations) {
      if (station.id == id) {
        return station;
      }
    }
    return null;
  }

  String stationName(String id) {
    final OfficialStation? station = stationById(id);
    if (station == null) {
      return id;
    }
    return station.nameEn;
  }

  OfficialTrain? trainById(String id) {
    for (final OfficialTrain train in trains) {
      if (train.id == id) {
        return train;
      }
    }
    return null;
  }

  factory OfficialDataset.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> coverage = _map(json, 'coverage');
    final Map<String, dynamic> documents = _map(json, 'documents');
    final Map<String, String> urls = <String, String>{};
    final Map<String, String> hashes = <String, String>{};
    documents.forEach((String key, dynamic value) {
      final Map<String, dynamic> document = value as Map<String, dynamic>;
      urls[key] = _string(document, 'pdf_url');
      hashes[key] = _string(document, 'sha256');
    });
    final List<dynamic> rawStations = _list(json, 'stations');
    final List<dynamic> rawTrains = _list(json, 'trains');
    final List<dynamic> gaps = _list(coverage, 'not_imported');
    return OfficialDataset(
      schemaVersion: _int(json, 'schema_version'),
      datasetId: _string(json, 'dataset_id'),
      timetableNumber: _string(json, 'timetable_number'),
      effectiveFrom: _string(json, 'effective_from'),
      retrieved: _string(json, 'retrieved'),
      lastVerified: _string(json, 'last_verified'),
      notice: _string(json, 'notice'),
      officialPortal: _string(json, 'official_portal'),
      intermediateStopsPublished: _bool(
        coverage,
        'intermediate_stops_published',
      ),
      importedSections: _stringList(coverage, 'imported'),
      coverageGaps: gaps
          .map(
            (dynamic entry) =>
                _string(entry as Map<String, dynamic>, 'section'),
          )
          .toList(growable: false),
      rowsTranscribed: _int(coverage, 'rows_transcribed'),
      rowsExcluded: _int(coverage, 'rows_excluded'),
      documentUrls: urls,
      documentHashes: hashes,
      stations: rawStations
          .map(
            (dynamic entry) =>
                OfficialStation.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      trains: rawTrains
          .map(
            (dynamic entry) =>
                OfficialTrain.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

/// Weekday names in the dataset vocabulary, indexed by DateTime.weekday.
const List<String> kWeekdayNames = <String>[
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// `monday` for [DateTime.monday], `sunday` for [DateTime.sunday].
String weekdayName(int weekday) {
  if (weekday < DateTime.monday || weekday > DateTime.sunday) {
    throw ArgumentError.value(weekday, 'weekday', 'must be 1..7');
  }
  return kWeekdayNames[weekday - 1];
}

/// Title-case label for a weekday name (`monday` -> `Monday`).
String weekdayLabel(String name) {
  if (name.isEmpty) {
    return name;
  }
  return name[0].toUpperCase() + name.substring(1);
}

/// Minutes since midnight for an `HH:MM` string.
int minutesOfDay(String hhmm) {
  final List<String> parts = hhmm.split(':');
  if (parts.length != 2) {
    throw FormatException('expected HH:MM, got "$hhmm"');
  }
  final int? hours = int.tryParse(parts[0]);
  final int? minutes = int.tryParse(parts[1]);
  if (hours == null ||
      minutes == null ||
      hours < 0 ||
      hours > 23 ||
      minutes < 0 ||
      minutes > 59) {
    throw FormatException('expected HH:MM, got "$hhmm"');
  }
  return hours * 60 + minutes;
}

/// `07:05` style formatting from minutes since midnight (mod 24h).
String formatMinutes(int minutes) {
  final int wrapped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60);
  final String hh = (wrapped ~/ 60).toString().padLeft(2, '0');
  final String mm = (wrapped % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

// --- strict JSON helpers -------------------------------------------------

String _string(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('missing or empty string field "$key"');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('field "$key" must be a string or null');
  }
  return value;
}

int _int(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value is! int) {
    throw FormatException('field "$key" must be an integer');
  }
  return value;
}

double _double(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value is! num) {
    throw FormatException('field "$key" must be a number');
  }
  return value.toDouble();
}

bool _bool(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value is! bool) {
    throw FormatException('field "$key" must be a boolean');
  }
  return value;
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('field "$key" must be an object');
  }
  return value;
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  final dynamic value = json[key];
  if (value is! List<dynamic>) {
    throw FormatException('field "$key" must be a list');
  }
  return value;
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  return _list(json, key)
      .map((dynamic entry) {
        if (entry is! String) {
          throw FormatException('field "$key" must contain strings');
        }
        return entry;
      })
      .toList(growable: false);
}

String _time(Map<String, dynamic> json, String key) {
  final String value = _string(json, key);
  minutesOfDay(value);
  return value;
}
