/// B07 — booking history list model + repository (APP-BOOK).
///
/// Pure Dart: no Flutter, no Supabase, no network. The repository accepts
/// injected [fetchRows] and [cancelRpc] functions so unit tests can supply
/// fakes; this slice performs ZERO direct Supabase client calls.
///
/// Schema facts (read-only, migration
/// `supabase/migrations/20260927063000_booking_atomic.sql` already applied
/// by the coordinator — workers never write migrations):
/// `public.bookings(user_id, trip_id, request_id, request_fingerprint,
/// status CONFIRMED|CANCELLED, total_fare_bdt, created_at, cancelled_at)`.
///
/// STOP CONDITION (contract): whole-booking cancellation ONLY via the
/// protected RPC `public.cancel_booking_service(p_user_id uuid,
/// p_booking_id uuid)` (owner-only, idempotent). This slice MUST NEVER
/// issue a direct client update of `trip_seats`/`bookings` — the repository
/// exposes only the injected [cancelRpc] path, and there is intentionally
/// no method that writes seat or booking rows directly. A repeat cancel of
/// an already-CANCELLED booking is a no-op success (`true`).
library;

/// Owned-booking status. Mirrors the `bookings.status` CHECK
/// (`CONFIRMED`|`CANCELLED`); anything else parses as [unknown] and must
/// render as an error state, never as a travel entitlement.
enum BookingStatus {
  /// Active demo booking; cancellable by its owner.
  confirmed,

  /// Whole booking cancelled; seats released server-side.
  cancelled,

  /// Unrecognized status payload — render as unavailable.
  unknown,
}

/// Owned-booking list row for the history screen.
///
/// All fields are display snapshots; cancelling never mutates this object —
/// the host re-lists after [BookingHistoryRepository.cancelOwned] succeeds.
class BookingSummary {
  /// Booking id (uuid string). Also the demo reference suffix.
  final String id;

  /// Owning user id (uuid string).
  final String userId;

  /// Trip id (uuid string).
  final String tripId;

  /// Current status.
  final BookingStatus status;

  /// Total fare in BDT.
  final int totalFareBdt;

  /// Row creation timestamp, if supplied.
  final DateTime? createdAt;

  /// Cancellation timestamp, if supplied.
  final DateTime? cancelledAt;

  const BookingSummary({
    required this.id,
    required this.userId,
    required this.tripId,
    required this.status,
    required this.totalFareBdt,
    this.createdAt,
    this.cancelledAt,
  });

  /// True for [BookingStatus.confirmed] rows (owner may cancel).
  bool get isActive => status == BookingStatus.confirmed;

  /// True for [BookingStatus.cancelled] rows (repeat cancel is a no-op).
  bool get isCancelled => status == BookingStatus.cancelled;

  /// Parses one booking row map.
  ///
  /// Throws [FormatException] when `id` is missing/blank or the fare is
  /// negative. Unknown status strings become [BookingStatus.unknown].
  factory BookingSummary.fromRow(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty) throw const FormatException('booking id missing');
    final fareRaw = row['total_fare_bdt'];
    final fare = fareRaw is int
        ? fareRaw
        : int.tryParse(fareRaw?.toString() ?? '');
    if (fare == null || fare < 0) {
      throw const FormatException('total_fare_bdt invalid');
    }
    final statusRaw = (row['status'] ?? '').toString().trim().toUpperCase();
    final status = switch (statusRaw) {
      'CONFIRMED' => BookingStatus.confirmed,
      'CANCELLED' => BookingStatus.cancelled,
      _ => BookingStatus.unknown,
    };
    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString());
    }

    return BookingSummary(
      id: id,
      userId: (row['user_id'] ?? '').toString(),
      tripId: (row['trip_id'] ?? '').toString(),
      status: status,
      totalFareBdt: fare,
      createdAt: parseDate(row['created_at']),
      cancelledAt: parseDate(row['cancelled_at']),
    );
  }
}

/// Injected row-fetch function: returns raw booking row maps for [ownerId].
///
/// Implemented by the host (Supabase query `bookings where user_id = owner`
/// ordered by `created_at desc`). Kept injectable so this slice stays
/// unit-testable with zero client imports.
typedef FetchBookingRows = Future<List<Map<String, dynamic>>> Function(
  String ownerId,
);

/// Injected cancel function: whole-booking cancel via the protected RPC
/// `cancel_booking_service(p_user_id, p_booking_id)`.
///
/// The host implementation MUST call that RPC (via the cancel-booking Edge
/// Function with a verified JWT) and never a direct table update. Returns
/// `true` on success including idempotent repeat-cancel.
typedef CancelBookingRpc = Future<bool> Function({
  required String ownerId,
  required String bookingId,
});

/// History + cancel repository for packet B07.
///
/// Account isolation: [listOwned] keeps only rows whose `user_id` equals
/// [ownerId] (when the row carries one); [cancelOwned] passes [ownerId]
/// through to the RPC, whose server-side `where id=... and user_id=...`
/// check makes non-owner cancel raise `NOT_FOUND` before any write.
class BookingHistoryRepository {
  /// Injected row fetch (host Supabase query).
  final FetchBookingRows fetchRows;

  /// Injected whole-booking cancel RPC call.
  final CancelBookingRpc cancelRpc;

  const BookingHistoryRepository({
    required this.fetchRows,
    required this.cancelRpc,
  });

  /// Lists bookings owned by [ownerId], newest first.
  ///
  /// Malformed rows are skipped (never crash the list). Throws
  /// [ArgumentError] when [ownerId] is blank.
  Future<List<BookingSummary>> listOwned(String ownerId) async {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Must not be blank');
    }
    final owner = ownerId.trim();
    final rows = await fetchRows(owner);
    final out = <BookingSummary>[];
    for (final row in rows) {
      final rowOwner = (row['user_id'] ?? '').toString();
      if (rowOwner.isNotEmpty && rowOwner != owner) continue;
      try {
        out.add(BookingSummary.fromRow(row));
      } on FormatException {
        continue;
      }
    }
    out.sort((a, b) {
      final ac = a.createdAt;
      final bc = b.createdAt;
      if (ac == null && bc == null) return 0;
      if (ac == null) return 1;
      if (bc == null) return -1;
      return bc.compareTo(ac);
    });
    return out;
  }

  /// Cancels the whole booking owned by [ownerId].
  ///
  /// STOP CONDITION: this is the ONLY write path in the slice and it goes
  /// exclusively through the injected [cancelRpc] (protected
  /// `cancel_booking_service` RPC). No direct update of `trip_seats` or
  /// `bookings` exists here by design. Idempotent: cancelling an already
  /// cancelled booking returns `true`. Throws [ArgumentError] on blank ids;
  /// RPC errors (e.g. `NOT_FOUND` for non-owner/unknown ids) propagate to
  /// the caller for UI mapping.
  Future<bool> cancelOwned({
    required String ownerId,
    required String bookingId,
  }) {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Must not be blank');
    }
    if (bookingId.trim().isEmpty) {
      throw ArgumentError.value(bookingId, 'bookingId', 'Must not be blank');
    }
    return cancelRpc(ownerId: ownerId.trim(), bookingId: bookingId.trim());
  }
}
