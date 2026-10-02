/// P10 — local recent-search history for the Home tab (V4
/// `09_HOME_SEARCH_SPEC.md`: max 5, never preseeded, tap restores).
///
/// The history is device-local interaction data, not server data: nothing is
/// uploaded and nothing is fetched. [RecentSearchStore] is the injectable
/// seam — [InMemoryRecentSearchStore] is the session default used by the Home
/// screen (hermetic), [SharedPreferencesRecentSearchStore] persists across
/// app launches and is wired by the coordinator (see P10 handoff).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/station.dart';
import '../search_date_utils.dart';

/// One remembered search: the two station ids plus the journey date that was
/// searched. Labels are a render-time snapshot of the live station names, used
/// only when the station catalog cannot be loaded (see
/// [RecentSearch.labelFor]).
class RecentSearch {
  final String originId;
  final String destinationId;
  final String originLabel;
  final String destinationLabel;
  final DateTime date;

  const RecentSearch({
    required this.originId,
    required this.destinationId,
    required this.originLabel,
    required this.destinationLabel,
    required this.date,
  });

  /// Dedupe key: the same route searched on a different date is a new entry;
  /// the same route+date replaces the old row in place.
  String get key =>
      '$originId>$destinationId@${dayStartOf(date).toIso8601String()}';

  /// Display label for [stationId]: the live station name when the catalog
  /// has it, otherwise the stored snapshot, otherwise an honest placeholder
  /// (never a blank row).
  String labelFor(
    String stationId,
    String storedLabel,
    List<Station> stations,
  ) {
    for (final Station station in stations) {
      if (station.id == stationId) return station.name;
    }
    final String snapshot = storedLabel.trim();
    return snapshot.isEmpty ? 'Station unavailable' : snapshot;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'origin_id': originId,
    'destination_id': destinationId,
    'origin_label': originLabel,
    'destination_label': destinationLabel,
    'date': dayStartOf(date).toIso8601String(),
  };

  /// Parses one stored row. Throws [FormatException] on missing ids/date so
  /// the store can skip corrupt entries instead of rendering nonsense.
  static RecentSearch fromJson(Map<String, dynamic> json) {
    final String originId = (json['origin_id'] ?? '').toString();
    final String destinationId = (json['destination_id'] ?? '').toString();
    final DateTime? date = DateTime.tryParse((json['date'] ?? '').toString());
    if (originId.isEmpty || destinationId.isEmpty || date == null) {
      throw const FormatException('recent search row is incomplete');
    }
    return RecentSearch(
      originId: originId,
      destinationId: destinationId,
      originLabel: (json['origin_label'] ?? '').toString(),
      destinationLabel: (json['destination_label'] ?? '').toString(),
      date: dayStartOf(date),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RecentSearch && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'RecentSearch($key)';
}

/// Injectable persistence seam for [RecentSearchesController].
abstract class RecentSearchStore {
  /// Stored entries, newest first. Implementations must never throw; a
  /// corrupt payload reads as an empty history.
  Future<List<RecentSearch>> read();

  /// Replaces the stored entries.
  Future<void> write(List<RecentSearch> entries);
}

/// Session-scoped store (default). Hermetic: nothing touches a platform
/// channel and the history clears when the process ends.
class InMemoryRecentSearchStore implements RecentSearchStore {
  List<RecentSearch> _entries;

  InMemoryRecentSearchStore([List<RecentSearch>? initial])
    : _entries = List<RecentSearch>.of(initial ?? const <RecentSearch>[]);

  @override
  Future<List<RecentSearch>> read() async => List<RecentSearch>.of(_entries);

  @override
  Future<void> write(List<RecentSearch> entries) async {
    _entries = List<RecentSearch>.of(entries);
  }
}

/// On-device store (SharedPreferences). Used when the coordinator injects it
/// so the history survives app restarts. Key is versioned; unreadable data
/// degrades to an empty history instead of throwing.
class SharedPreferencesRecentSearchStore implements RecentSearchStore {
  static const String storageKey = 'railmate_bd.home.recent_searches.v1';

  @override
  Future<List<RecentSearch>> read() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return <RecentSearch>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <RecentSearch>[];
      final List<RecentSearch> out = <RecentSearch>[];
      for (final Object? row in decoded) {
        if (row is! Map) continue;
        try {
          out.add(RecentSearch.fromJson(Map<String, dynamic>.from(row)));
        } on FormatException {
          continue; // skip corrupt row, keep the rest honest
        }
      }
      return out;
    } catch (_) {
      return <RecentSearch>[];
    }
  }

  @override
  Future<void> write(List<RecentSearch> entries) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (entries.isEmpty) {
        await prefs.remove(storageKey);
        return;
      }
      await prefs.setString(
        storageKey,
        jsonEncode(<Map<String, dynamic>>[
          for (final RecentSearch e in entries) e.toJson(),
        ]),
      );
    } catch (_) {
      // Persistence is best-effort: a failing local write never blocks search.
    }
  }
}

/// Owns the recent-search list and notifies the Home section.
///
/// History is only ever written from a real submitted search, so it can never
/// be preseeded as if the traveller searched something.
class RecentSearchesController extends ChangeNotifier {
  /// Pack cap: the five most recent searches.
  static const int maxEntries = 5;

  /// Upper bound on the initial store read. Exceeding it settles the section
  /// on its empty state rather than showing an indefinite skeleton.
  static const Duration loadTimeout = Duration(seconds: 2);

  final RecentSearchStore store;

  List<RecentSearch> _entries = <RecentSearch>[];
  bool _loaded = false;
  int _revision = 0;

  RecentSearchesController({required this.store});

  /// Newest first.
  List<RecentSearch> get entries => List<RecentSearch>.unmodifiable(_entries);

  /// True once [load] has completed. False means "not known yet" — the UI
  /// shows a skeleton, never an invented empty state.
  bool get isLoaded => _loaded;

  /// Bumped on every mutation so widget tests can await the async store write
  /// without sleeping.
  int get revision => _revision;

  /// Reads the store once. Safe to call repeatedly; only the first call does
  /// I/O.
  ///
  /// A store that never completes (a platform channel that is unavailable —
  /// which is exactly what happens in a widget test, and could also happen on
  /// a device with a broken storage provider) must not leave the UI shimmering
  /// forever. The read is therefore bounded by [loadTimeout]: on timeout, or
  /// on any error, the controller settles as *loaded* with no entries, and the
  /// section shows its honest "No recent searches" state. A history that
  /// failed to load is never presented as a history that does not exist, and
  /// it never blocks the rest of Home.
  Future<void> load() async {
    if (_loaded) return;
    List<RecentSearch> read;
    try {
      read = await store.read().timeout(loadTimeout);
    } catch (_) {
      read = const <RecentSearch>[];
    }
    _entries = _normalise(read);
    _loaded = true;
    _revision++;
    notifyListeners();
  }

  /// Records a completed search: newest first, deduped by
  /// [RecentSearch.key], capped at [maxEntries].
  Future<void> record(RecentSearch entry) async {
    final List<RecentSearch> next = <RecentSearch>[
      entry,
      for (final RecentSearch e in _entries)
        if (e.key != entry.key) e,
    ];
    await _commit(next);
  }

  /// Removes the whole history (explicit "Clear all").
  Future<void> clear() async => _commit(<RecentSearch>[]);

  Future<void> _commit(List<RecentSearch> next) async {
    _entries = _normalise(next);
    _loaded = true;
    _revision++;
    notifyListeners();
    await store.write(_entries);
  }

  List<RecentSearch> _normalise(List<RecentSearch> raw) {
    final List<RecentSearch> out = <RecentSearch>[];
    final Set<String> seen = <String>{};
    for (final RecentSearch entry in raw) {
      if (entry.originId.isEmpty || entry.destinationId.isEmpty) continue;
      if (entry.originId == entry.destinationId) continue;
      if (!seen.add(entry.key)) continue;
      out.add(entry);
      if (out.length == maxEntries) break;
    }
    return out;
  }
}

// Re-exported so the shell can name the concrete persistent store without
// importing the shared barrel.
