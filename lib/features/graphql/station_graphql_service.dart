/// B04 — GraphQL-first station loading used by the search flow.
///
/// The search lane owns its files; this lane only exposes the functions, so
/// nothing under `lib/features/search/` is modified here.
///
/// Intended single call site (owned by the search lane, NOT wired here):
/// the home search station dropdown load path — currently
/// `SearchState.loadStations()` in `lib/features/search/search_state.dart`,
/// which feeds the From/To dropdowns in
/// `lib/features/search/home_search_screen.dart`. That call site should try
/// [fetchStationList] (GraphQL) first and fall back to the existing REST
/// `SearchApi.fetchStations()` on [GraphqlNetworkError], e.g. via
/// [fetchStationListWithFallback]:
///
/// ```dart
/// // Search-lane wiring sketch (do NOT paste blindly; search lane owns it):
/// import 'package:railmate_bd/features/graphql/station_graphql_service.dart';
/// stations = await fetchStationListWithFallback(
///   graphql: graphqlClient,
///   restFallback: restApi.fetchStations, // SupabaseSearchApi.fetchStations
/// );
/// ```
library;

import '../search/models/station.dart';
import 'graphql_client.dart';

/// REST fallback used when GraphQL is unreachable.
///
/// Pass the search lane's `SearchApi.fetchStations` (the PostgREST
/// implementation in `lib/features/search/search_repository.dart`). Kept as
/// a plain closure type so this file does not depend on the search lane's
/// Supabase client wiring.
typedef RestStationsFallback = Future<List<Station>> Function();

/// Runs the B04 read-only GraphQL station query.
///
/// Returns stations ordered by name. Throws [GraphqlNetworkError],
/// [GraphqlResponseError] or [GraphqlMalformedError] — never an empty list
/// on failure (empty means the query succeeded with zero rows).
Future<List<Station>> fetchStationList(StationGraphqlClient client) {
  return client.queryStations();
}

/// GraphQL-first station load with REST fallback.
///
/// Tries [fetchStationList] via [graphql]; on [GraphqlNetworkError] only
/// (transport/timeout — the case where the hosted endpoint is unreachable),
/// calls [restFallback] instead. [GraphqlResponseError] and
/// [GraphqlMalformedError] are rethrown without fallback: they signal a
/// contract/schema problem that retrying over REST would only mask.
Future<List<Station>> fetchStationListWithFallback({
  required StationGraphqlClient graphql,
  required RestStationsFallback restFallback,
}) async {
  try {
    return await fetchStationList(graphql);
  } on GraphqlNetworkError {
    return restFallback();
  }
}
