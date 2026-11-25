/// P43 - loads the bundled official timetable and caches it for the session.
///
/// The bundled asset is authoritative. A network copy can be supplied (the same
/// JSON is published read-only on GitHub Pages) but it is only consulted when a
/// caller explicitly asks for a refresh, and any failure leaves the bundled
/// copy in place. There is no Supabase table for this data.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'official_train.dart';

/// Path of the bundled dataset inside the Flutter assets.
const String kOfficialTimetableAsset = 'assets/data/official-timetable.json';

/// Signature for a JSON text loader, so tests never touch the asset bundle.
typedef JsonTextLoader = Future<String> Function();

/// Signature for an optional remote refresh.
typedef JsonTextFetcher = Future<String> Function();

/// Loads, parses and caches [OfficialDataset].
class TimetableRepository {
  TimetableRepository({JsonTextLoader? loadBundled, this.fetchRemote})
    : loadBundled = loadBundled ?? _loadFromAsset;

  /// Loads the bundled JSON (the asset bundle by default).
  final JsonTextLoader loadBundled;

  /// Optional remote copy of the same JSON; used only by [refresh].
  final JsonTextFetcher? fetchRemote;

  OfficialDataset? _cached;
  Future<OfficialDataset>? _inFlight;

  /// The dataset currently in memory, if it has been loaded.
  OfficialDataset? get cached => _cached;

  /// Loads the bundled dataset once; concurrent callers share one future.
  Future<OfficialDataset> load() {
    final OfficialDataset? ready = _cached;
    if (ready != null) {
      return Future<OfficialDataset>.value(ready);
    }
    final Future<OfficialDataset>? pending = _inFlight;
    if (pending != null) {
      return pending;
    }
    final Future<OfficialDataset> future = loadBundled()
        .then(_parse)
        .whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  /// Tries the remote copy (when one was supplied) and falls back to the
  /// bundled copy. A malformed or unreachable remote payload is reported to the
  /// caller but never replaces good bundled data.
  Future<OfficialDataset> refresh({bool keepOnFailure = true}) async {
    final JsonTextFetcher? fetcher = fetchRemote;
    if (fetcher == null) {
      return load();
    }
    try {
      final String text = await fetcher();
      final OfficialDataset parsed = _parse(text);
      _cached = parsed;
      return parsed;
    } catch (error) {
      if (!keepOnFailure) {
        rethrow;
      }
      final OfficialDataset fallback = await load();
      return fallback;
    }
  }

  /// Clears the cache (tests and account switches).
  void invalidate() {
    _cached = null;
    _inFlight = null;
  }

  OfficialDataset _parse(String text) {
    final OfficialDataset parsed = parseOfficialDataset(text);
    _cached = parsed;
    return parsed;
  }

  static Future<String> _loadFromAsset() =>
      rootBundle.loadString(kOfficialTimetableAsset);
}

/// Parses dataset JSON with strict validation; throws [FormatException] on any
/// shape problem so a corrupt asset surfaces as an honest error state.
OfficialDataset parseOfficialDataset(String text) {
  final dynamic decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('official timetable root must be an object');
  }
  final OfficialDataset dataset = OfficialDataset.fromJson(decoded);
  if (dataset.trains.isEmpty) {
    throw const FormatException('official timetable has no train rows');
  }
  if (dataset.stations.isEmpty) {
    throw const FormatException('official timetable has no stations');
  }
  final Set<String> stationIds = dataset.stations
      .map((OfficialStation s) => s.id)
      .toSet();
  for (final OfficialTrain train in dataset.trains) {
    if (!stationIds.contains(train.originStation) ||
        !stationIds.contains(train.destinationStation)) {
      throw FormatException(
        'train ${train.trainNumber} references an undeclared station',
      );
    }
  }
  return dataset;
}
