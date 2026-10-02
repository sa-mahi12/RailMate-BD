/// P10 — upcoming-booking seam for the Home tab (V4
/// `09_HOME_SEARCH_SPEC.md`: "Only render real signed-in booking if one
/// exists... Never fabricate").
///
/// The Home tab lives in the search feature, one layer below the shell that
/// owns `AppDependencies`, so this slice does NOT reach for a repository: it
/// defines a plain display model ([UpcomingBooking]) plus an injectable loader
/// ([LoadUpcomingBooking]). The coordinator owns the exact wiring (P10
/// handoff):
///
/// ```dart
/// UpcomingBookingSection(
///   signedIn: uid != null,
///   loader: uid == null
///       ? null
///       : () async {
///           final rows = await deps.historyFor(uid).listOwned(uid);
///           final upcoming = rows.where((b) => b.isActive).firstOrNull;
///           return upcoming == null
///               ? null
///               : UpcomingBooking(
///                   reference: displayReferenceForBookingId(upcoming.id),
///                   originLabel: ...,     // from the trip row
///                   destinationLabel: ...,
///                   serviceLabel: ...,
///                   departureAt: ...,
///                   seatCodes: const <String>[],
///                 );
///         },
///   onViewBooking: () => ...,
/// )
/// ```
///
/// Every state the widget can render (loading, signed out, none, failure,
/// real booking) is honest: the empty card is shown instead of an invented
/// booking, and a loader failure is reported as a failure.
library;

/// Read-only display snapshot of one upcoming demo booking.
///
/// Every field is supplied by the caller (host data). Nothing here is derived
/// from demo fixtures, so the widget cannot invent a journey.
class UpcomingBooking {
  /// Human booking reference (display form of the server-issued booking id).
  final String reference;

  /// Origin station label, e.g. `DAC` or `Dhaka`.
  final String originLabel;

  /// Destination station label.
  final String destinationLabel;

  /// Service/train label, e.g. `Subarna Express (Demo)`.
  final String serviceLabel;

  /// Scheduled departure.
  final DateTime departureAt;

  /// Arrival when the host has it; null renders the departure only.
  final DateTime? arrivalAt;

  /// Seat labels for the booking (`A1`, `B3`, ...). Empty renders a neutral
  /// "seats not loaded" line rather than a made-up count.
  final List<String> seatCodes;

  const UpcomingBooking({
    required this.reference,
    required this.originLabel,
    required this.destinationLabel,
    required this.serviceLabel,
    required this.departureAt,
    required this.seatCodes,
    this.arrivalAt,
  });

  /// `DAC → CGP`.
  String get routeLabel => '$originLabel → $destinationLabel';

  /// `A1, B3` or an honest placeholder when no seat rows were loaded.
  String get seatsLabel =>
      seatCodes.isEmpty ? 'Seats not listed' : seatCodes.join(', ');
}

/// Injected loader seam: returns the traveller's next upcoming booking, or
/// null when there is none. Throwing is treated as a load failure (shown as
/// such), never as "no bookings".
typedef LoadUpcomingBooking = Future<UpcomingBooking?> Function();
