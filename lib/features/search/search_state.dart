import 'package:flutter/foundation.dart';

import 'models/station.dart';
import 'models/trip.dart';
import 'search_date_utils.dart';
import 'search_repository.dart';

/// Lifecycle of a trip search. `loaded` covers both hits and the empty
/// case — check [isEmpty] / [results] to tell them apart.
enum SearchStatus { idle, loading, loaded, error }

/// Error flavour for [SearchStatus.error]. Timeouts are tracked separately
/// so the UI can never render a timeout as "no trains".
enum SearchErrorKind { none, network, timeout }

/// ChangeNotifier holding the trip-search form and result state.
///
/// Holds the station list, selected origin/destination/date and results.
/// The repository is injected ([SearchApi]) so widget tests can supply a
/// fake. All dates are explicit: [selectedDate] is initialised to today's
/// calendar date and every screen must display it.
class SearchState extends ChangeNotifier {
  final SearchApi api;

  SearchState({required this.api});

  SearchStatus status = SearchStatus.idle;
  SearchErrorKind errorKind = SearchErrorKind.none;
  String? errorMessage;

  List<Station> stations = <Station>[];
  Station? origin;
  Station? destination;
  DateTime selectedDate = dayStartOf(DateTime.now());
  List<Trip> results = <Trip>[];

  /// True when the last search succeeded with zero rows (the repository
  /// signals this via [EmptyResult], normalised here to an empty list).
  bool get isEmpty => status == SearchStatus.loaded && results.isEmpty;

  bool get isLoading => status == SearchStatus.loading;

  /// Origin/destination code for header cards; `--` when unknown.
  String stationCode(String id) {
    for (final station in stations) {
      if (station.id == id) return station.code;
    }
    return '--';
  }

  /// Origin/destination display name for header cards; `--` when unknown.
  String stationName(String id) {
    for (final station in stations) {
      if (station.id == id) return station.name;
    }
    return '--';
  }

  Future<void> loadStations() async {
    status = SearchStatus.loading;
    errorKind = SearchErrorKind.none;
    errorMessage = null;
    notifyListeners();
    try {
      stations = await api.fetchStations();
      status = SearchStatus.idle;
    } on NetworkError catch (e) {
      status = SearchStatus.error;
      errorKind = e.isTimeout
          ? SearchErrorKind.timeout
          : SearchErrorKind.network;
      errorMessage = e.message;
    }
    notifyListeners();
  }

  void selectOrigin(Station? station) {
    origin = station;
    notifyListeners();
  }

  void selectDestination(Station? station) {
    destination = station;
    notifyListeners();
  }

  void swapEndpoints() {
    final previous = origin;
    origin = destination;
    destination = previous;
    notifyListeners();
  }

  void selectDate(DateTime date) {
    selectedDate = dayStartOf(date);
    notifyListeners();
  }

  /// Form validation for the home screen. Returns a user-facing message
  /// or null when the selection is valid. Rules: origin != destination
  /// and the date must not be in the past.
  String? validateSelection() {
    if (origin == null || destination == null) {
      return 'Please choose origin and destination stations.';
    }
    if (origin!.id == destination!.id) {
      return 'Origin and destination must be different.';
    }
    if (isPastCalendarDate(selectedDate)) {
      return 'Journey date cannot be in the past.';
    }
    return null;
  }

  /// Runs the trip query for the current selection. Validation failures
  /// surface as [errorMessage] without touching the repository.
  Future<void> search() async {
    final validationError = validateSelection();
    if (validationError != null) {
      status = SearchStatus.error;
      errorKind = SearchErrorKind.none;
      errorMessage = validationError;
      notifyListeners();
      return;
    }
    status = SearchStatus.loading;
    errorKind = SearchErrorKind.none;
    errorMessage = null;
    notifyListeners();
    try {
      results = await api.searchTrips(
        originId: origin!.id,
        destinationId: destination!.id,
        date: selectedDate,
      );
      status = SearchStatus.loaded;
    } on EmptyResult {
      // Successful query, zero rows: loaded + empty, NOT an error.
      results = <Trip>[];
      status = SearchStatus.loaded;
    } on NetworkError catch (e) {
      // Network/timeout failures stay in error and must never read as
      // "no trains".
      results = <Trip>[];
      status = SearchStatus.error;
      errorKind = e.isTimeout
          ? SearchErrorKind.timeout
          : SearchErrorKind.network;
      errorMessage = e.message;
    }
    notifyListeners();
  }

  /// Re-runs the last search (used by results-screen retry buttons).
  Future<void> retry() => search();
}
