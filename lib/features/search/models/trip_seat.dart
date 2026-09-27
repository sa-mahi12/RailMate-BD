import 'dart:convert';

/// Pure data model mirroring `public.trip_seats` (one-coach demo layout
/// seeded in `supabase/seed/02_demo_trips_seats.sql`).
///
/// `bookingId == null` means the seat is free inventory. No
/// Supabase/network dependency; seat reservation stays server-side.
class TripSeat {
  final String id;
  final String tripId;
  final String seatCode;
  final String? bookingId;

  const TripSeat({
    required this.id,
    required this.tripId,
    required this.seatCode,
    this.bookingId,
  });

  /// Free (unbooked) demo inventory.
  bool get isAvailable => bookingId == null;

  factory TripSeat.fromMap(Map<String, dynamic> map) {
    final booking = map['booking_id'];
    return TripSeat(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      seatCode: map['seat_code'] as String,
      bookingId: booking == null ? null : booking as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'trip_id': tripId,
      'seat_code': seatCode,
      'booking_id': bookingId,
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
          bookingId == other.bookingId;

  @override
  int get hashCode => Object.hash(id, tripId, seatCode, bookingId);
}
