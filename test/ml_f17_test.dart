import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/ml/trip_ranker.dart';
import 'package:railmate_bd/features/search/models/trip.dart';

Trip fixtureTrip(
  String id, {
  int fare = 700,
  int depHour = 8,
  int durationMin = 240,
}) {
  final DateTime dep = DateTime(2026, 10, 15, depHour);
  return Trip(
    id: id,
    trainName: 'DEMO Ranker',
    originStationId: 'o',
    destinationStationId: 'd',
    departureAt: dep,
    arrivalAt: dep.add(Duration(minutes: durationMin)),
    fareBdt: fare,
    active: true,
  );
}

void main() {
  test('feature extraction matches ml/metadata.json constants exactly', () {
    expect(RankerModelSpec.featureOrder, [
      'fare_norm',
      'duration_norm',
      'departure_hour_norm',
      'seats_ratio',
      'transfers_norm',
    ]);
    // Boundary row: exact zeros/ones.
    final List<double> boundary = TripRanker.normalizeTrip(
      fixtureTrip('b', fare: 50, depHour: 0, durationMin: 30),
      1.0,
    );
    expect(boundary, [0.0, 0.0, 0.0, 1.0, 0.0]);
    // Mid row from metadata normalization:
    // fare (150-50)/1950, duration (90-30)/690, hour 7/24, seats 0.9.
    final List<double> mid = TripRanker.normalizeTrip(
      fixtureTrip('m', fare: 150, depHour: 7, durationMin: 90),
      0.9,
    );
    expect(mid.length, 5);
    expect(mid[0], closeTo(100 / 1950, 1e-12));
    expect(mid[1], closeTo(60 / 690, 1e-12));
    expect(mid[2], closeTo(7 / 24, 1e-12));
    expect(mid[3], closeTo(0.9, 1e-12));
    expect(mid[4], 0.0);
  });

  test('stable re-rank with fake scorer: ties keep the input order', () async {
    final List<Trip> input = [
      fixtureTrip('t1'),
      fixtureTrip('t2'),
      fixtureTrip('t3'),
    ];
    final Map<String, double> scores = {'t1': 0.9, 't2': 0.9, 't3': 0.1};
    final RankResult result = await rankTripsWithScorer(
      input,
      (Trip trip) async => scores[trip.id]!,
    );
    expect(result.usedMl, isTrue);
    expect(result.note, isNull);
    // Tie t1/t2 keeps fetch order; t3 sinks.
    expect(result.trips.map((t) => t.id), ['t1', 't2', 't3']);

    final Map<String, double> reversed = {'t1': 0.1, 't2': 0.2, 't3': 0.3};
    final RankResult reranked = await rankTripsWithScorer(
      input,
      (Trip trip) async => reversed[trip.id]!,
    );
    expect(reranked.trips.map((t) => t.id), ['t3', 't2', 't1']);
    expect(reranked.usedMl, isTrue);
  });

  test(
    'scorer failure degrades to unranked passthrough with honest note',
    () async {
      final List<Trip> input = [
        fixtureTrip('t1'),
        fixtureTrip('t2'),
        fixtureTrip('t3'),
      ];
      Future<double> throwing(Trip trip) async {
        if (trip.id == 't2') throw Exception('interpreter gone');
        return 0.9;
      }

      final RankResult failed = await rankTripsWithScorer(input, throwing);
      expect(failed.usedMl, isFalse);
      expect(failed.note, smartRankingUnavailableNote);
      expect(failed.note, contains('smart ranking unavailable'));
      // Input order preserved, nothing dropped.
      expect(failed.trips.map((t) => t.id), ['t1', 't2', 't3']);

      // NaN scores degrade the same honest way.
      final RankResult nan = await rankTripsWithScorer(
        input,
        (_) async => double.nan,
      );
      expect(nan.usedMl, isFalse);
      expect(nan.note, smartRankingUnavailableNote);
      expect(nan.trips.map((t) => t.id), ['t1', 't2', 't3']);
    },
  );

  test('never invents or drops trips on success or failure', () async {
    final List<Trip> input = [
      fixtureTrip('a', fare: 150),
      fixtureTrip('b', fare: 1800),
      fixtureTrip('c', fare: 600),
      fixtureTrip('d', fare: 300),
    ];
    final Map<String, double> scores = {'a': 0.8, 'b': 0.1, 'c': 0.5, 'd': 0.5};
    final RankResult ok = await rankTripsWithScorer(
      input,
      (Trip trip) async => scores[trip.id]!,
    );
    expect(ok.trips.length, input.length);
    expect(ok.trips.map((t) => t.id).toSet(), {'a', 'b', 'c', 'd'});
    expect(ok.trips, isNotEmpty);

    Future<double> boom(Trip trip) async => throw Exception('no model');
    final RankResult failed = await rankTripsWithScorer(input, boom);
    expect(failed.trips.length, input.length);
    expect(failed.trips.map((t) => t.id).toSet(), {'a', 'b', 'c', 'd'});
    // Failure is never an empty list for non-empty input.
    expect(failed.trips, isNotEmpty);
  });

  test(
    'TripRanker.rankResult: unloadable model keeps fetch order honestly',
    () async {
      final TripRanker ranker = TripRanker(
        interpreterLoader: () => throw Exception('no model'),
      );
      final List<Trip> input = [fixtureTrip('x'), fixtureTrip('y')];
      final RankResult result = await ranker.rankResult(input);
      expect(result.usedMl, isFalse);
      expect(result.note, smartRankingUnavailableNote);
      expect(result.trips.map((t) => t.id), ['x', 'y']);
      expect(result.trips, isNotEmpty);
      expect(ranker.isMl, isFalse);
      ranker.close();

      // Null/empty stay empty with no note (nothing failed to rank).
      final TripRanker idle = TripRanker(
        interpreterLoader: () => throw Exception('no model'),
      );
      expect((await idle.rankResult(null)).trips, isEmpty);
      expect((await idle.rankResult(null)).note, isNull);
      expect((await idle.rankResult([])).trips, isEmpty);
      idle.close();
    },
  );
}
