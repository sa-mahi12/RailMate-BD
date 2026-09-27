import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/ml/trip_ranker.dart';
import 'package:railmate_bd/features/search/models/trip.dart';

Trip trip({required int fare, required DateTime dep, required DateTime arr}) =>
    Trip(
      id: 't',
      trainName: 'DEMO X',
      originStationId: 'o',
      destinationStationId: 'd',
      departureAt: dep,
      arrivalAt: arr,
      fareBdt: fare,
      active: true,
    );

void main() {
  test('normalization matches metadata constants exactly', () {
    final f = TripRanker.normalizeTrip(
      trip(
        fare: 50,
        dep: DateTime(2026, 1, 1, 0, 0),
        arr: DateTime(2026, 1, 1, 0, 30),
      ),
      1.0,
    );
    expect(f, [0.0, 0.0, 0.0, 1.0, 0.0]); // boundaries
    final g = TripRanker.normalizeTrip(
      trip(
        fare: 2000,
        dep: DateTime(2026, 1, 1, 23, 0),
        arr: DateTime(2026, 1, 1, 23, 0).add(const Duration(hours: 12)),
      ),
      2.5,
      9,
    ); // over-range clamps
    expect(g, [1.0, 1.0, 23 / 24, 1.0, 1.0]);
  });

  test('fallback math equals sigmoid(w.x+b)', () {
    const w = [
      -4.474987405099812,
      -5.899226015070247,
      -5.47519223546818,
      10.423080315229784,
      0.0,
    ];
    const b = 2.0768424250538073;
    final f = [0.2, 0.3, 0.25, 0.8, 0.0];
    double z = b;
    for (var i = 0; i < 5; i++) {
      z += w[i] * f[i];
    }
    expect(
      DartFallbackScorer.scoreFeatures(f),
      closeTo(1.0 / (1.0 + math.exp(-z)), 1e-12),
    );
  });

  test('negatives: null/empty/NaN + fallback flag', () async {
    final r = TripRanker(interpreterLoader: () => throw Exception('no model'));
    expect(await r.rankTrips(null), isEmpty);
    expect(await r.rankTrips([]), isEmpty);
    expect(DartFallbackScorer.isMl, isFalse);
    final s = await r.score(
      trip(
        fare: 700,
        dep: DateTime(2026, 1, 1, 8),
        arr: DateTime(2026, 1, 1, 12),
      ),
      double.nan,
    );
    expect(s.isNaN, isFalse);
    expect(r.usingFallback, isTrue);
    expect(r.isMl, isFalse);
    expect(r.displayLabel, fallbackRankingLabel);
    expect(() => DartFallbackScorer.scoreFeatures([0.1]), throwsArgumentError);
    r.close();
  });
}
