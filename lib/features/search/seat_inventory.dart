import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/trip_seat.dart';
import 'search_repository.dart';

/// Hosted seat-inventory reader for one trip (F02 seed, F05 demo horizon).
///
/// Reads `public.trip_seats` filtered by `trip_id`, ordered by `seat_code`.
/// Effective unavailable rule (formalised by the F05 corrective migration,
/// pending coordinator apply): a seat is unavailable when
/// `booking_id IS NOT NULL OR demo_reserved = true`. Rows with
/// `demo_reserved = true` and no `booking_id` are reported unavailable by
/// mapping them onto a reserved marker here, so the UI treats demo-held and
/// really-booked seats identically without this reader ever writing.
/// Read-only: never writes `booking_id` (booking stays server-side in the
/// A05/F07 lane) and never touches `demo_reserved` (owned by the
/// `refresh_demo_horizon()` owner/admin function, which itself never
/// overwrites `booking_id`).
Future<List<TripSeat>> fetchTripSeats(
  SupabaseClient client,
  String tripId,
) async {
  try {
    final rows = await client
        .from('trip_seats')
        .select()
        .eq('trip_id', tripId)
        .order('seat_code', ascending: true)
        .timeout(SupabaseSearchApi.queryTimeout);
    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (map['demo_reserved'] == true && map['booking_id'] == null) {
        map['booking_id'] = 'demo-reserved';
      }
      return TripSeat.fromMap(map);
    }).toList();
  } on TimeoutException {
    throw const NetworkError('Seat request timed out', isTimeout: true);
  } catch (e) {
    if (e is NetworkError) rethrow;
    throw NetworkError('Seat request failed: $e');
  }
}
