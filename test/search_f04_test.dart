import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/graphql/graphql_client.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';
import 'package:railmate_bd/features/search/search_state.dart';

const Station graphqlDhaka = Station(
  id: '11111111-1111-4111-8111-111111111111',
  code: 'DAC',
  name: 'Dhaka',
);
const Station graphqlChattogram = Station(
  id: '22222222-2222-4222-8222-222222222222',
  code: 'CGP',
  name: 'Chattogram',
);
const Station restOnly = Station(
  id: '99999999-9999-4999-8999-999999999999',
  code: 'KHL',
  name: 'Khulna',
);

/// REST fake with an observable station-fetch count (proves GraphQL-first
/// ordering vs fallback without any network).
class CountingSearchApi implements SearchApi {
  CountingSearchApi({this.stations = const [], this.stationsError});

  final List<Station> stations;
  final Object? stationsError;
  int fetchStationsCalls = 0;

  @override
  Future<List<Station>> fetchStations() async {
    fetchStationsCalls++;
    if (stationsError != null) throw stationsError!;
    return stations;
  }

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) async {
    throw const EmptyResult('unused in F04');
  }
}

Map<String, dynamic> graphqlStationsBody(List<Station> stations) =>
    <String, dynamic>{
      'data': <String, dynamic>{
        'stationsCollection': <String, dynamic>{
          'edges': <dynamic>[
            for (final s in stations)
              <String, dynamic>{
                'node': <String, dynamic>{
                  'id': s.id,
                  'code': s.code,
                  'name': s.name,
                },
              },
          ],
        },
      },
    };

StationGraphqlClient graphqlWith(GraphqlSender sender) => StationGraphqlClient(
  supabaseUrl: 'https://x.supabase.co',
  anonKey: 'test-anon-key',
  sender: sender,
);

void main() {
  test('F04: GraphQL-first ordering — REST fallback NOT called', () async {
    final api = CountingSearchApi(stations: [restOnly]);
    final graphql = graphqlWith(
      (uri, headers, body) async =>
          // Deliberately unsorted: client must sort by name
          // (Chattogram before Dhaka) to match REST order behaviour.
          graphqlStationsBody([graphqlDhaka, graphqlChattogram]),
    );
    final state = SearchState(api: api, graphqlClient: graphql);

    await state.loadStations();

    expect(state.status, SearchStatus.idle);
    expect(state.stations.map((s) => s.code).toList(), <String>['CGP', 'DAC']);
    expect(api.fetchStationsCalls, 0);
  });

  test(
    'F04: REST fallback on GraphqlNetworkError (transport/timeout)',
    () async {
      final api = CountingSearchApi(stations: [restOnly]);
      final graphql = graphqlWith(
        (uri, headers, body) async =>
            throw const GraphqlNetworkError('unreachable', isTimeout: true),
      );
      final state = SearchState(api: api, graphqlClient: graphql);

      await state.loadStations();

      expect(state.status, SearchStatus.idle);
      expect(state.stations.map((s) => s.code).toList(), <String>['KHL']);
      expect(api.fetchStationsCalls, 1);
    },
  );

  test('F04: GraphQL down + REST timeout surfaces error/timeout', () async {
    final api = CountingSearchApi(
      stationsError: const NetworkError('timed out', isTimeout: true),
    );
    final graphql = graphqlWith(
      (uri, headers, body) async =>
          throw const GraphqlNetworkError('unreachable'),
    );
    final state = SearchState(api: api, graphqlClient: graphql);

    await state.loadStations();

    expect(state.status, SearchStatus.error);
    expect(state.errorKind, SearchErrorKind.timeout);
    expect(state.stations, isEmpty);
    expect(api.fetchStationsCalls, 1);
  });

  test('F04: NO fallback on GraphqlResponseError (contract problem)', () async {
    final api = CountingSearchApi(stations: [restOnly]);
    final graphql = graphqlWith(
      (uri, headers, body) async => <String, dynamic>{
        'errors': <dynamic>[
          <String, dynamic>{'message': 'permission denied for table stations'},
        ],
      },
    );
    final state = SearchState(api: api, graphqlClient: graphql);

    await state.loadStations();

    expect(state.status, SearchStatus.error);
    expect(state.errorKind, SearchErrorKind.network);
    expect(state.errorMessage, contains('permission denied'));
    expect(state.stations, isEmpty);
    // REST must NOT mask a schema/contract failure.
    expect(api.fetchStationsCalls, 0);
  });

  test('F04: NO fallback on GraphqlMalformedError', () async {
    final api = CountingSearchApi(stations: [restOnly]);
    final graphql = graphqlWith(
      (uri, headers, body) async => <String, dynamic>{'data': null},
    );
    final state = SearchState(api: api, graphqlClient: graphql);

    await state.loadStations();

    expect(state.status, SearchStatus.error);
    expect(state.errorKind, SearchErrorKind.network);
    expect(state.stations, isEmpty);
    expect(api.fetchStationsCalls, 0);
  });

  test(
    'F04: backward compatible — absent graphqlClient uses REST only',
    () async {
      final api = CountingSearchApi(
        stations: [graphqlDhaka, graphqlChattogram],
      );
      final state = SearchState(api: api);

      await state.loadStations();

      expect(state.status, SearchStatus.idle);
      expect(state.stations.length, 2);
      expect(api.fetchStationsCalls, 1);
    },
  );
}
