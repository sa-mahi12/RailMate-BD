import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';
import 'package:railmate_bd/features/search/search_state.dart';

const Station dhaka = Station(
  id: '11111111-1111-4111-8111-111111111111',
  code: 'DAC',
  name: 'Dhaka',
);
const Station khulna = Station(
  id: '99999999-9999-4999-8999-999999999999',
  code: 'KHL',
  name: 'Khulna',
);

Trip demoTrip(String id, String name) => Trip.fromMap({
  'id': id,
  'train_name': name,
  'origin_station_id': dhaka.id,
  'destination_station_id': khulna.id,
  'departure_at': '2026-10-15T07:00:00+06:00',
  'arrival_at': '2026-10-15T12:30:00+06:00',
  'fare_bdt': 700,
  'active': true,
});

class FakeSearchApi implements SearchApi {
  FakeSearchApi({this.trips = const [], this.error, this.searchCalls = 0});

  final List<Trip> trips;
  final Object? error;
  int searchCalls;

  @override
  Future<List<Station>> fetchStations() async => [dhaka, khulna];

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) async {
    searchCalls++;
    if (error != null) throw error!;
    return trips;
  }
}

void main() {
  test('search returns trips for supported route/date', () async {
    final state = SearchState(
      api: FakeSearchApi(
        trips: [demoTrip('t1', 'DEMO A'), demoTrip('t2', 'DEMO B')],
      ),
    );
    await state.loadStations();
    state.selectOrigin(dhaka);
    state.selectDestination(khulna);
    state.selectDate(DateTime(2026, 10, 15));
    await state.search();
    expect(state.status, SearchStatus.loaded);
    expect(state.results.length, 2);
    expect(state.isEmpty, isFalse);
  });

  test('unsupported route yields empty state, not error', () async {
    final state = SearchState(
      api: FakeSearchApi(error: const EmptyResult('none')),
    );
    await state.loadStations();
    state.selectOrigin(dhaka);
    state.selectDestination(khulna);
    state.selectDate(DateTime(2026, 10, 15));
    await state.search();
    expect(state.status, SearchStatus.loaded);
    expect(state.isEmpty, isTrue);
    expect(state.errorKind, SearchErrorKind.none);
  });

  test('timeout surfaces error/timeout, never empty', () async {
    final state = SearchState(
      api: FakeSearchApi(
        error: const NetworkError('timed out', isTimeout: true),
      ),
    );
    await state.loadStations();
    state.selectOrigin(dhaka);
    state.selectDestination(khulna);
    state.selectDate(DateTime(2026, 10, 15));
    await state.search();
    expect(state.status, SearchStatus.error);
    expect(state.errorKind, SearchErrorKind.timeout);
    expect(state.isEmpty, isFalse);
  });

  test(
    'same origin and destination is rejected without repository call',
    () async {
      final api = FakeSearchApi();
      final state = SearchState(api: api);
      state.selectOrigin(dhaka);
      state.selectDestination(dhaka);
      await state.search();
      expect(state.status, SearchStatus.error);
      expect(api.searchCalls, 0);
      expect(state.errorMessage, contains('different'));
    },
  );
}
