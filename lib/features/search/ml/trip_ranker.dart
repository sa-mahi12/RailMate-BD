import 'dart:math' show exp;

import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/trip.dart';

/// Label the search UI must show next to ML-produced scores.
///
/// Wording is fixed by the product contract: experimental ranking from
/// demonstration data — never a claim about observed commuter demand or
/// real prediction accuracy.
const String experimentRankingLabel =
    'experimental ranking from demonstration data';

/// Label the search UI must show when scores did NOT come from the
/// on-device model.
///
/// This is explicitly NON-ML: a deterministic sigmoid computation in pure
/// Dart. Requirement R-12 is PASSED only with true on-device model
/// execution ([TripRanker] with a loaded [Interpreter]), never with this
/// fallback.
const String fallbackRankingLabel =
    'NON-ML deterministic fallback ranking (demonstration data)';

/// Bundled-model constants from `ml/ranker_weights.json` (model a09-v1).
///
/// Duplicated here as `const` so the pure-Dart fallback needs no asset
/// bundle access and no extra dependency. The TFLite file itself
/// (`assets/models/ranker.tflite`, 5 float32 inputs -> 1 float32 output)
/// carries the same weights via the hosted A09 conversion.
class RankerModelSpec {
  /// Bundled asset path, must be declared under `flutter/assets` in
  /// pubspec.yaml by the coordinator.
  static const String assetPath = 'assets/models/ranker.tflite';

  /// Feature order: [fare_norm, duration_norm, departure_hour_norm,
  /// seats_ratio, transfers_norm].
  static const List<String> featureOrder = <String>[
    'fare_norm',
    'duration_norm',
    'departure_hour_norm',
    'seats_ratio',
    'transfers_norm',
  ];

  static const List<double> weights = <double>[
    -4.474987405099812,
    -5.899226015070247,
    -5.47519223546818,
    10.423080315229784,
    0.0,
  ];

  static const double bias = 2.0768424250538073;
}

/// One trip with its relevance score (higher = more relevant).
class RankedTrip {
  final Trip trip;
  final double score;

  const RankedTrip({required this.trip, required this.score});
}

double _clamp(double value, double min, double max) {
  if (value.isNaN) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

double _clamp01(double value) => _clamp(value, 0.0, 1.0);

/// Pure-Dart sigmoid math shared by the fallback scorer.
///
/// NOT machine learning: identical arithmetic to the model's single
/// dense layer, executed as ordinary Dart code with no interpreter.
double _sigmoid(double z) {
  final double clamped = _clamp(z, -60.0, 60.0);
  return 1.0 / (1.0 + exp(-clamped));
}

// ---------------------------------------------------------------------------
// NON-ML FALLBACK. Read this before using: this class is NOT machine
// learning. It replays the ranker weights as plain Dart arithmetic for use
// ONLY when the real TFLite interpreter cannot be loaded or run. Any UI
// showing these scores must use [fallbackRankingLabel], never
// [experimentRankingLabel].
// ---------------------------------------------------------------------------

/// Deterministic pure-Dart replay of the ranker math.
///
/// NON-ML FALLBACK: no model is loaded, no inference runs. Exists so search
/// still returns ordered results (labelled non-ML) when the TFLite
/// interpreter is unavailable.
class DartFallbackScorer {
  /// Always false. This flag is how callers/tests prove the fallback path
  /// is never mistaken for on-device ML.
  static const bool isMl = false;

  const DartFallbackScorer();

  /// Score an already-normalized 5-element feature vector.
  ///
  /// Throws [ArgumentError] for wrong-length input. NaN entries are
  /// sanitized to 0.0 so a corrupt feature can never poison a ranking.
  static double scoreFeatures(List<double> features) {
    if (features.length != RankerModelSpec.weights.length) {
      throw ArgumentError(
        'Expected ${RankerModelSpec.weights.length} features, '
        'got ${features.length}.',
      );
    }
    double z = RankerModelSpec.bias;
    for (var i = 0; i < features.length; i++) {
      final double v = features[i].isNaN ? 0.0 : features[i];
      z += RankerModelSpec.weights[i] * v;
    }
    final double score = _sigmoid(z);
    return score.isNaN ? 0.0 : score;
  }

  /// Normalize then score a single [Trip].
  double scoreTrip(Trip trip, double seatsRatio, [int transfers = 0]) {
    return scoreFeatures(TripRanker.normalizeTrip(trip, seatsRatio, transfers));
  }
}

/// On-device search ranker backed by the real TFLite interpreter.
///
/// This is the ONLY ML path in the app: scores come from
/// `assets/models/ranker.tflite` executed via `tflite_flutter`
/// [Interpreter]. When the interpreter cannot be loaded (or a run throws),
/// scoring degrades to [DartFallbackScorer] and [usingFallback] flips to
/// true so the UI can show [fallbackRankingLabel] instead of
/// [experimentRankingLabel].
class TripRanker {
  static const double defaultSeatsRatio = 1.0;

  final Future<Interpreter> Function() _loader;

  Interpreter? _interpreter;
  bool _loadAttempted = false;
  bool _loadFailed = false;
  bool _runFailed = false;
  bool _lastScoreUsedFallback = false;

  /// [interpreterLoader] is injectable for tests; defaults to loading the
  /// bundled asset. Production use: `TripRanker()`.
  TripRanker({Future<Interpreter> Function()? interpreterLoader})
    : _loader =
          interpreterLoader ??
          (() => Interpreter.fromAsset(RankerModelSpec.assetPath));

  /// True once the interpreter asset has loaded (lazy; see [ensureLoaded]).
  bool get isLoaded => _interpreter != null;

  /// True when the interpreter asset failed to load.
  bool get loadFailed => _loadFailed;

  /// True when the last [score] call fell back to pure-Dart math.
  bool get lastScoreUsedFallback => _lastScoreUsedFallback;

  /// True once any fallback has been used (load failure or run failure).
  /// When true, the UI must label results non-ML.
  bool get usingFallback => _loadFailed || _runFailed || _lastScoreUsedFallback;

  /// True only while scores are produced by the real on-device model.
  bool get isMl => isLoaded && !usingFallback;

  /// UI label reflecting the actual scoring path used so far.
  String get displayLabel =>
      usingFallback ? fallbackRankingLabel : experimentRankingLabel;

  /// Lazily loads the interpreter. Safe to call repeatedly; records
  /// failure instead of throwing so callers degrade to the fallback.
  Future<void> ensureLoaded() async {
    if (_interpreter != null || _loadAttempted) return;
    _loadAttempted = true;
    try {
      _interpreter = await _loader();
    } catch (_) {
      _loadFailed = true;
      _interpreter = null;
    }
  }

  /// Normalizes a [Trip] into the 5-element feature vector in
  /// [RankerModelSpec.featureOrder], implementing `ml/metadata.json`
  /// EXACTLY:
  ///
  /// - fare_norm = (fareBdt - 50) / 1950, clamped 0..1
  /// - duration_norm = (minutes - 30) / 690, clamped 0..1
  /// - departure_hour_norm = clamp(hour, 0, 23) / 24
  /// - seats_ratio = clamp(seatsRatio, 0, 1)
  /// - transfers_norm = clamp(transfers, 0, 2) / 2 (always 0 in v1)
  ///
  /// NaN inputs sanitize to the range minimum (0.0).
  static List<double> normalizeTrip(
    Trip trip,
    double seatsRatio, [
    int transfers = 0,
  ]) {
    final double fareNorm = _clamp01((trip.fareBdt - 50) / 1950);
    final double durationMinutes = trip.arrivalAt
        .difference(trip.departureAt)
        .inMinutes
        .toDouble();
    final double durationNorm = _clamp01((durationMinutes - 30) / 690);
    final double hourNorm =
        _clamp(trip.departureAt.hour.toDouble(), 0, 23) / 24;
    final double seatsNorm = _clamp01(seatsRatio);
    final double transfersNorm = _clamp(transfers.toDouble(), 0, 2) / 2;
    return <double>[fareNorm, durationNorm, hourNorm, seatsNorm, transfersNorm];
  }

  double _runInterpreter(List<double> features) {
    final Interpreter interpreter = _interpreter!;
    final List<List<double>> input = <List<double>>[
      List<double>.from(features),
    ];
    final List<List<double>> output = List<List<double>>.generate(
      1,
      (_) => <double>[0.0],
    );
    interpreter.run(input, output);
    return output[0][0];
  }

  /// Scores one trip: real interpreter inference when available, otherwise
  /// the explicitly NON-ML [DartFallbackScorer].
  ///
  /// Never throws for model failures; NaN model output falls back to Dart
  /// math (double-sanitized to 0.0 as a last resort).
  Future<double> score(
    Trip trip,
    double seatsRatio, {
    int transfers = 0,
  }) async {
    final List<double> features = normalizeTrip(trip, seatsRatio, transfers);
    await ensureLoaded();
    if (isLoaded) {
      try {
        final double raw = _runInterpreter(features);
        if (!raw.isNaN) {
          _lastScoreUsedFallback = false;
          return raw;
        }
      } catch (_) {
        _runFailed = true;
      }
    }
    _lastScoreUsedFallback = true;
    return DartFallbackScorer.scoreFeatures(features);
  }

  /// Ranks trips by score descending. Null/empty input returns `[]`.
  ///
  /// [seatsRatioOf] supplies per-trip remaining-seat ratios; trips without
  /// a value use [defaultSeatsRatio] (1.0 = fully available).
  Future<List<RankedTrip>> rankTrips(
    List<Trip>? trips, {
    double Function(Trip trip)? seatsRatioOf,
  }) async {
    if (trips == null || trips.isEmpty) return <RankedTrip>[];
    final List<RankedTrip> ranked = <RankedTrip>[];
    for (final Trip trip in trips) {
      final double ratio = seatsRatioOf?.call(trip) ?? defaultSeatsRatio;
      ranked.add(RankedTrip(trip: trip, score: await score(trip, ratio)));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  /// Releases the interpreter. Idempotent; safe to call more than once.
  void close() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Flutter-[State]-friendly alias for [close].
  void dispose() => close();
}
