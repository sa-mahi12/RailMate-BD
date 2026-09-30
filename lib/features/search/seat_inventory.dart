import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/trip_seat.dart';
import 'search_repository.dart';

/// Hosted seat-inventory reader for one trip (F02 seed, F05 demo horizon).
///
/// Reads `public.trip_seats` filtered by `trip_id`, ordered by `seat_code`.
/// Effective unavailable rule (server-enforced in `book_trip_service`): a
/// seat is unavailable when `booking_id IS NOT NULL OR demo_reserved =
/// true`. Rows with `demo_reserved = true` and no `booking_id` are passed
/// through with the real flag ([TripSeat.demoReserved]) so the UI treats
/// demo-held and really-booked seats as identically disabled without this
/// reader ever synthesising a `booking_id` or writing anything.
/// Read-only: never writes `booking_id` (booking stays server-side in the
/// A05/F07 lane) and never touches `demo_reserved` (owned by the
/// `refresh_demo_horizon()` owner/admin function, which itself never
/// overwrites `booking_id`).
///
/// Columns are selected explicitly so a missing/renamed column surfaces
/// as a query error, never as silently wrong availability.
///
/// NOTE (F06 hermetic testing): [fetchTripSeats] takes a real
/// [SupabaseClient] and is therefore verified live by the coordinator
/// (F21 device run). The row mapping itself is the pure [mapSeatRow]
/// function below, unit-tested hermetically in `test/seat_f06_test.dart`.
///
/// Pure row mapper: converts one `trip_seats` row into a [TripSeat],
/// carrying the real `demo_reserved` flag through. Never synthesises a
/// `booking_id` — demo-held rows keep `bookingId == null` with
/// `demoReserved == true`.
TripSeat mapSeatRow(Map<String, dynamic> row) =>
    TripSeat.fromMap(Map<String, dynamic>.from(row));

Future<List<TripSeat>> fetchTripSeats(
  SupabaseClient client,
  String tripId,
) async {
  try {
    final rows = await client
        .from('trip_seats')
        .select('id,trip_id,seat_code,booking_id,demo_reserved')
        .eq('trip_id', tripId)
        .order('seat_code', ascending: true)
        .timeout(SupabaseSearchApi.queryTimeout);
    return (rows as List)
        .map((row) => mapSeatRow(row as Map<String, dynamic>))
        .toList();
  } on TimeoutException {
    throw const NetworkError('Seat request timed out', isTimeout: true);
  } catch (e) {
    if (e is NetworkError) rethrow;
    throw NetworkError('Seat request failed: $e');
  }
}
