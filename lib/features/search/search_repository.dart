import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/station.dart';
import 'models/trip.dart';

/// Distinct failure when hosted Supabase cannot be reached or the query
/// fails (transport error, server error, or timeout).
///
/// [isTimeout] is true only for deadline/connection timeouts so callers can
/// surface a retry affordance. A timeout must NEVER be displayed as
/// "no trains".
class NetworkError implements Exception {
  final String message;
  final bool isTimeout;

  const NetworkError(this.message, {this.isTimeout = false});

  @override
  String toString() => 'NetworkError: $message';
}

/// Distinct outcome when a trip query succeeds but matches zero rows.
///
/// Kept separate from [NetworkError] so empty routes/dates render the
/// "No trains on this route/date" empty state instead of an error.
class EmptyResult implements Exception {
  final String message;

  const EmptyResult(this.message);

  @override
  String toString() => 'EmptyResult: $message';
}

/// Injectable Supabase query interface for trip search.
///
/// Tests inject a fake implementation; production code uses
/// [SupabaseSearchApi]. Every method takes an explicit [DateTime] where a
/// date matters — there are no hidden "today" defaults in this layer.
abstract class SearchApi {
  /// All stations ordered by name.
  Future<List<Station>> fetchStations();

  /// Active trips for one route on one calendar date.
  ///
  /// Throws [EmptyResult] when the query succeeds with zero rows and
  /// [NetworkError] when the backend cannot be reached.
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  });
}

/// Real hosted-Supabase implementation of [SearchApi].
///
/// Coordinator wiring (no secrets involved; auth uses the public anon key
/// configured once at app startup):
///
/// ```dart
/// final api = SupabaseSearchApi(Supabase.instance.client);
/// ```
class SupabaseSearchApi implements SearchApi {
  static const Duration queryTimeout = Duration(seconds: 15);

  final SupabaseClient client;

  const SupabaseSearchApi(this.client);

  @override
  Future<List<Station>> fetchStations() async {
    try {
      final rows = await client
          .from('stations')
          .select()
          .order('name', ascending: true)
          .timeout(queryTimeout);
      return (rows as List)
          .map((row) => Station.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on TimeoutException {
      throw const NetworkError('Station request timed out', isTimeout: true);
    } catch (e) {
      if (e is NetworkError) rethrow;
      throw NetworkError('Station request failed: $e');
    }
  }

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) async {
    // Explicit calendar-day range on departure_at in local time.
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    try {
      final rows = await client
          .from('trips')
          .select()
          .eq('origin_station_id', originId)
          .eq('destination_station_id', destinationId)
          .eq('active', true)
          .gte('departure_at', dayStart.toIso8601String())
          .lt('departure_at', dayEnd.toIso8601String())
          .order('departure_at', ascending: true)
          .timeout(queryTimeout);
      final trips = (rows as List)
          .map((row) => Trip.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      if (trips.isEmpty) {
        throw EmptyResult(
          'No trains for this route on ${dayStart.year}-${dayStart.month}-${dayStart.day}',
        );
      }
      return trips;
    } on TimeoutException {
      throw const NetworkError('Trip search timed out', isTimeout: true);
    } catch (e) {
      if (e is NetworkError || e is EmptyResult) rethrow;
      throw NetworkError('Trip search failed: $e');
    }
  }
}
