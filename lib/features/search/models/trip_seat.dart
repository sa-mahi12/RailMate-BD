import 'dart:convert';

/// Pure data model mirroring `public.trip_seats` (one-coach demo layout
/// seeded in `supabase/seed/02_demo_trips_seats.sql`, F05 demo horizon).
///
/// A seat is free inventory only when `bookingId == null` AND
/// `demoReserved == false`. `demoReserved` mirrors the server-owned
/// `demo_reserved` flag (set by `refresh_demo_horizon()`, enforced in
/// `book_trip_service`); this client layer never writes it — seats are
/// DISPLAY ONLY here. No Supabase/network dependency; seat reservation
/// stays server-side.
class TripSeat {
  final String id;
  final String tripId;
  final String seatCode;
  final String? bookingId;

  /// True when the server holds this seat for the demo horizon
  /// (`demo_reserved = true` with no `booking_id`). Held seats render
  /// UNAVAILABLE (disabled), exactly like booked seats.
  final bool demoReserved;

  const TripSeat({
    required this.id,
    required this.tripId,
    required this.seatCode,
    this.bookingId,
    this.demoReserved = false,
  });

  /// Free (selectable) demo inventory.
  bool get isAvailable => bookingId == null && !demoReserved;

  /// True when this seat is held by the demo horizon but not really
  /// booked (`demo_reserved = true`, `booking_id IS NULL`). The UI may
  /// use this for a distinct "Reserved" shade; the seat stays disabled.
  bool get isDemoHeld => demoReserved && bookingId == null;

  factory TripSeat.fromMap(Map<String, dynamic> map) {
    final booking = map['booking_id'];
    return TripSeat(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      seatCode: map['seat_code'] as String,
      bookingId: booking == null ? null : booking as String,
      // Backward compat: rows without the column (old seeds) parse as false.
      demoReserved: map['demo_reserved'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'trip_id': tripId,
      'seat_code': seatCode,
      'booking_id': bookingId,
      'demo_reserved': demoReserved,
    };
  }

  factory TripSeat.fromJson(String source) =>
      TripSeat.fromMap(json.decode(source) as Map<String, dynamic>);

  String toJson() => json.encode(toMap());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripSeat &&
          id == other.id &&
          tripId == other.tripId &&
          seatCode == other.seatCode &&
          bookingId == other.bookingId &&
          demoReserved == other.demoReserved;

  @override
  int get hashCode =>
      Object.hash(id, tripId, seatCode, bookingId, demoReserved);
}
