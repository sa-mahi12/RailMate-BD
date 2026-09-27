/// B04 — minimal Supabase pg_graphql POST client (RailMate BD).
///
/// One read-only station query, actually invoked via
/// [StationGraphqlClient.queryStations] (see
/// `station_graphql_service.dart`). No new pub dependency: the default
/// sender uses `dart:io` [HttpClient]. `package:http` is NOT used (absent
/// from pubspec; adding it is forbidden for this packet).
///
/// Auth: the Supabase publishable (anon) key is passed as a constructor
/// parameter — never hardcoded here. The endpoint is derived as
/// `<supabaseUrl>/graphql/v1`, e.g.
/// `https://<ref>.supabase.co/graphql/v1`.
///
/// Error taxonomy (all distinct):
/// * [GraphqlNetworkError] — transport failure, non-2xx status, or timeout.
/// * [GraphqlResponseError] — HTTP 200 with a non-empty GraphQL `errors`
///   array (e.g. RLS denial, unknown field after schema drift).
/// * [GraphqlMalformedError] — 200 without `errors`, but the body is not
///   JSON or lacks the expected `data.stationsCollection.edges[].node`
///   shape.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../search/models/station.dart';

/// Injectable HTTP sender for GraphQL POST.
///
/// Takes the endpoint [uri], headers and the JSON-serialisable [body], and
/// returns the decoded JSON response object. Tests inject a fake; production
/// uses [ioGraphqlSender]. Any transport-level failure must surface as
/// [GraphqlNetworkError] so callers never mistake it for an empty result.
typedef GraphqlSender = Future<Map<String, dynamic>> Function(
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> body,
);

/// Transport failure (unreachable host, non-2xx status, or timeout).
///
/// [isTimeout] is true only for deadline/connection timeouts so callers can
/// surface a retry affordance. A timeout must NEVER render as "no stations".
class GraphqlNetworkError implements Exception {
  final String message;
  final bool isTimeout;

  const GraphqlNetworkError(this.message, {this.isTimeout = false});

  @override
  String toString() => 'GraphqlNetworkError: $message';
}

/// HTTP 200 response carrying a non-empty GraphQL `errors` array.
class GraphqlResponseError implements Exception {
  final String message;
  final List<String> errors;

  const GraphqlResponseError(this.message, [this.errors = const <String>[]]);

  @override
  String toString() => 'GraphqlResponseError: $message';
}

/// HTTP 200 response that is not JSON or lacks the expected data shape.
class GraphqlMalformedError implements Exception {
  final String message;

  const GraphqlMalformedError(this.message);

  @override
  String toString() => 'GraphqlMalformedError: $message';
}

/// Default [GraphqlSender] built on `dart:io` [HttpClient].
///
/// Throws [GraphqlNetworkError] on timeouts, socket errors and non-2xx
/// statuses, and [GraphqlMalformedError] when the body is not a JSON object.
Future<Map<String, dynamic>> ioGraphqlSender(
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> body, {
  Duration timeout = StationGraphqlClient.requestTimeout,
}) async {
  final HttpClient httpClient = HttpClient();
  try {
    final HttpClientRequest request = await httpClient
        .postUrl(uri)
        .timeout(timeout);
    for (final MapEntry<String, String> header in headers.entries) {
      request.headers.set(header.key, header.value);
    }
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final HttpClientResponse response = await request.close().timeout(timeout);
    final String text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GraphqlNetworkError(
        'GraphQL request failed with HTTP ${response.statusCode}',
      );
    }
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      throw GraphqlMalformedError('GraphQL response body is not a JSON object');
    } on FormatException catch (e) {
      throw GraphqlMalformedError('GraphQL response is not valid JSON: $e');
    }
  } on TimeoutException {
    throw const GraphqlNetworkError(
      'GraphQL request timed out',
      isTimeout: true,
    );
  } on SocketException catch (e) {
    throw GraphqlNetworkError('GraphQL request failed: $e');
  } on HttpException catch (e) {
    throw GraphqlNetworkError('GraphQL request failed: $e');
  } finally {
    httpClient.close();
  }
}

/// Minimal read-only pg_graphql client for the stations table.
///
/// ```dart
/// final client = StationGraphqlClient(
///   supabaseUrl: config.supabaseUrl, // e.g. https://<ref>.supabase.co
///   anonKey: config.supabaseAnonKey, // publishable key, never service-role
/// );
/// final List<Station> stations = await client.queryStations();
/// ```
class StationGraphqlClient {
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Read-only station query against pg_graphql's collection entrypoint for
  /// `public.stations`. Requests only `id code name`; rows are sorted
  /// client-side by name to match the REST `order('name')` behaviour without
  /// depending on version-specific `orderBy` enum spelling.
  static const String stationsQuery =
      'query Stations { stationsCollection { edges { node { id code name } } } }';

  /// Hosted Supabase project URL, e.g. `https://<ref>.supabase.co`.
  final String supabaseUrl;

  /// Supabase publishable (anon) key. Never a service-role key.
  final String anonKey;

  /// Injectable sender; defaults to [ioGraphqlSender].
  final GraphqlSender sender;

  const StationGraphqlClient({
    required this.supabaseUrl,
    required this.anonKey,
    this.sender = ioGraphqlSender,
  });

  /// GraphQL endpoint derived from [supabaseUrl].
  Uri get endpoint =>
      Uri.parse('${supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/graphql/v1');

  /// Runs [stationsQuery] and returns stations ordered by name.
  ///
  /// Throws [GraphqlNetworkError], [GraphqlResponseError] or
  /// [GraphqlMalformedError]; never returns an empty list silently on
  /// failure (an empty list means the query succeeded with zero rows).
  Future<List<Station>> queryStations() async {
    final Map<String, String> headers = <String, String>{
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
    };
    final Map<String, dynamic> body = <String, dynamic>{'query': stationsQuery};
    late final Map<String, dynamic> decoded;
    try {
      decoded = await sender(endpoint, headers, body);
    } on GraphqlNetworkError {
      rethrow;
    } on TimeoutException {
      throw const GraphqlNetworkError(
        'GraphQL request timed out',
        isTimeout: true,
      );
    } catch (e) {
      // A fake sender surfacing a raw transport failure still counts as a
      // network error, never as malformed or empty.
      throw GraphqlNetworkError('GraphQL request failed: $e');
    }

    final dynamic errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final List<String> messages = <String>[
        for (final dynamic entry in errors)
          if (entry is Map && entry['message'] is String)
            entry['message'] as String
          else
            entry.toString(),
      ];
      throw GraphqlResponseError(
        'GraphQL query returned errors: ${messages.join('; ')}',
        messages,
      );
    }

    final dynamic data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const GraphqlMalformedError(
        'GraphQL response is missing the "data" object',
      );
    }
    final dynamic collection = data['stationsCollection'];
    if (collection is! Map<String, dynamic>) {
      throw const GraphqlMalformedError(
        'GraphQL response is missing "data.stationsCollection"',
      );
    }
    final dynamic edges = collection['edges'];
    if (edges is! List) {
      throw const GraphqlMalformedError(
        'GraphQL response "stationsCollection.edges" is not a list',
      );
    }
    final List<Station> stations = <Station>[];
    for (final dynamic edge in edges) {
      if (edge is! Map<String, dynamic>) {
        throw const GraphqlMalformedError(
          'GraphQL edge entry is not an object',
        );
      }
      final dynamic node = edge['node'];
      if (node is! Map<String, dynamic>) {
        throw const GraphqlMalformedError(
          'GraphQL edge is missing its "node" object',
        );
      }
      final dynamic id = node['id'];
      final dynamic code = node['code'];
      final dynamic name = node['name'];
      if (id is! String || code is! String || name is! String) {
        throw const GraphqlMalformedError(
          'GraphQL station node needs String "id", "code" and "name"',
        );
      }
      stations.add(Station(id: id, code: code, name: name));
    }
    stations.sort((Station a, Station b) => a.name.compareTo(b.name));
    return stations;
  }
}
