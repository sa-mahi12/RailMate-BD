import 'package:flutter/foundation.dart';

import '../graphql/graphql_client.dart';
import '../graphql/station_graphql_service.dart';
import 'ml/trip_ranker.dart';
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

  /// Optional GraphQL-first station source (F04). When present,
  /// [loadStations] tries `fetchStationListWithFallback(graphql:
  /// graphqlClient, restFallback: api.fetchStations)` — GraphQL first with
  /// REST fallback on transport/timeout ([GraphqlNetworkError]) only. When
  /// absent, [loadStations] uses the REST [api] directly (F02 behaviour, kept
  /// backward compatible so existing call sites and tests keep passing).
  ///
  /// Wiring lives with the coordinator (owner of `home_shell.dart`):
  /// `SearchState(api: deps.searchApi, graphqlClient: deps.graphql)`.
  final StationGraphqlClient? graphqlClient;

  SearchState({required this.api, this.graphqlClient});

  SearchStatus status = SearchStatus.idle;
  SearchErrorKind errorKind = SearchErrorKind.none;
  String? errorMessage;

  List<Station> stations = <Station>[];
  Station? origin;
  Station? destination;
  DateTime selectedDate = dayStartOf(DateTime.now());
  List<Trip> results = <Trip>[];

  /// On-device smart ranker (F17, worker-D lane instance owned here so the
  /// TFLite interpreter loads once per search state, not once per search).
  /// Lazily loads the bundled model; failures degrade honestly (see below).
  final TripRanker ranker = TripRanker();

  /// Honest ranking note for the results screen (F17): null when the list
  /// is ML-ranked (or when no ranking ran: validation/empty/error paths);
  /// set to [smartRankingUnavailableNote] when inference could not run and
  /// the list is the unranked fetch order.
  String? rankingNote;

  @override
  void dispose() {
    ranker.dispose();
    super.dispose();
  }

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
      final StationGraphqlClient? graphql = graphqlClient;
      if (graphql != null) {
        stations = await fetchStationListWithFallback(
          graphql: graphql,
          restFallback: api.fetchStations,
        );
      } else {
        stations = await api.fetchStations();
      }
      status = SearchStatus.idle;
    } on NetworkError catch (e) {
      status = SearchStatus.error;
      errorKind = e.isTimeout
          ? SearchErrorKind.timeout
          : SearchErrorKind.network;
      errorMessage = e.message;
    } on GraphqlResponseError catch (e) {
      // No REST fallback by contract (schema/contract problem, not transport):
      // surface as a network-flavoured error, never as "no stations".
      status = SearchStatus.error;
      errorKind = SearchErrorKind.network;
      errorMessage = e.message;
    } on GraphqlMalformedError catch (e) {
      status = SearchStatus.error;
      errorKind = SearchErrorKind.network;
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
      final List<Trip> fetched = await api.searchTrips(
        originId: origin!.id,
        destinationId: destination!.id,
        date: selectedDate,
      );
      // F17: on-device smart re-rank. Failure keeps the fetch order with an
      // honest note (never invented/dropped trips, never silent).
      final RankResult rank = await ranker.rankResult(fetched);
      results = rank.trips;
      rankingNote = rank.note;
      status = SearchStatus.loaded;
    } on EmptyResult {
      // Successful query, zero rows: loaded + empty, NOT an error.
      results = <Trip>[];
      rankingNote = null;
      status = SearchStatus.loaded;
    } on NetworkError catch (e) {
      // Network/timeout failures stay in error and must never read as
      // "no trains".
      results = <Trip>[];
      rankingNote = null;
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
