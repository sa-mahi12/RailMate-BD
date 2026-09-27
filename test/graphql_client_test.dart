import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/graphql/graphql_client.dart';

Map<String, dynamic> okBody() => <String, dynamic>{
  'data': <String, dynamic>{
    'stationsCollection': <String, dynamic>{
      'edges': <dynamic>[
        <String, dynamic>{
          'node': <String, dynamic>{
            'id': '22222222-2222-2222-2222-222222222222',
            'code': 'DHK',
            'name': 'Dhaka',
          },
        },
        <String, dynamic>{
          'node': <String, dynamic>{
            'id': '11111111-1111-1111-1111-111111111111',
            'code': 'CTG',
            'name': 'Chattogram',
          },
        },
      ],
    },
  },
};

StationGraphqlClient fakeClient(GraphqlSender sender) => StationGraphqlClient(
  supabaseUrl: 'https://x.supabase.co',
  anonKey: 'test-anon-key',
  sender: sender,
);

void main() {
  test('parses stations and sorts by name', () async {
    Uri? seenUri;
    Map<String, String>? seenHeaders;
    Map<String, dynamic>? seenBody;
    final client = fakeClient((uri, headers, body) async {
      seenUri = uri;
      seenHeaders = headers;
      seenBody = body;
      return okBody();
    });
    final stations = await client.queryStations();
    expect(seenUri.toString(), 'https://x.supabase.co/graphql/v1');
    expect(seenHeaders!['apikey'], 'test-anon-key');
    expect((seenBody!['query'] as String), contains('stationsCollection'));
    expect(stations.map((s) => s.code).toList(), <String>['CTG', 'DHK']);
  });

  test('NEGATIVE: GraphQL errors array -> GraphqlResponseError', () async {
    final client = fakeClient(
      (uri, headers, body) async => <String, dynamic>{
        'errors': <dynamic>[
          <String, dynamic>{'message': 'permission denied for table stations'},
        ],
      },
    );
    expect(client.queryStations(), throwsA(isA<GraphqlResponseError>()));
  });

  test('NEGATIVE: missing data shape -> GraphqlMalformedError', () async {
    final client = fakeClient(
      (uri, headers, body) async => <String, dynamic>{'data': null},
    );
    expect(client.queryStations(), throwsA(isA<GraphqlMalformedError>()));
  });

  test('NEGATIVE: transport failure -> GraphqlNetworkError', () async {
    final client = fakeClient(
      (uri, headers, body) async =>
          throw const GraphqlNetworkError('unreachable', isTimeout: true),
    );
    expect(client.queryStations(), throwsA(isA<GraphqlNetworkError>()));
  });
}
