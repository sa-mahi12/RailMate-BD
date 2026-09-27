import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_form_state.dart';

/// Confirmed-booking snapshot for packet A06 (demonstration e-ticket).
///
/// Pure Dart: no Flutter, no Supabase, no network. The ticket lane never
/// fetches anything itself — the host passes an already-confirmed snapshot
/// in (via [TicketData.fromForm] over the B05 [PassengerFormState] contract
/// plus a plain booking-reference string), so this slice needs no Supabase
/// calls.
///
/// Every rendered artifact built from this model must state
/// [demoBanner] — demonstration tickets grant no travel entitlement.
class TicketData {
  /// One-line banner every ticket artifact must display.
  static const String demoBanner =
      'DEMONSTRATION TICKET \u2014 NOT VALID FOR TRAVEL';

  /// Supporting note for ticket footers / PDF metadata.
  static const String demoNote =
      'Demonstration only. Invalid for travel. No real money was charged.';

  /// Server-issued booking reference (e.g. `BDR5F9K3`).
  final String bookingReference;

  /// Confirmed passengers, each bound to exactly one seat code.
  final List<Passenger> passengers;

  /// Fare numbers in BDT: `passengerCount`, `farePerSeat`, `baseFare`,
  /// `serviceCharge`, `total` (mirrors the B05 fareBreakdown shape).
  final Map<String, int> fareBreakdown;

  /// Total payable in BDT (base + service charge).
  final int totalBdt;

  /// Optional display labels for the trip; empty means "not provided".
  final String trainLabel;
  final String fromLabel;
  final String toLabel;
  final String departLabel;

  TicketData({
    required this.bookingReference,
    required List<Passenger> passengers,
    required Map<String, int> fareBreakdown,
    required this.totalBdt,
    this.trainLabel = '',
    this.fromLabel = '',
    this.toLabel = '',
    this.departLabel = '',
  }) : passengers = List<Passenger>.unmodifiable(passengers),
       fareBreakdown = Map<String, int>.unmodifiable(fareBreakdown);

  /// Builds a ticket snapshot from the B05 form contract.
  ///
  /// Copies (never aliases) the passenger list, fare breakdown and total so
  /// later form edits cannot mutate an already-issued ticket.
  factory TicketData.fromForm({
    required PassengerFormState form,
    required String bookingReference,
    String trainLabel = '',
    String fromLabel = '',
    String toLabel = '',
    String departLabel = '',
  }) {
    return TicketData(
      bookingReference: bookingReference,
      passengers: List<Passenger>.of(form.passengers),
      fareBreakdown: Map<String, int>.of(form.fareBreakdown),
      totalBdt: form.totalBdt,
      trainLabel: trainLabel,
      fromLabel: fromLabel,
      toLabel: toLabel,
      departLabel: departLabel,
    );
  }

  /// Booking references are 6–16 ASCII alphanumerics (e.g. `BDR5F9K3`).
  static bool isValidReference(String reference) {
    return RegExp(r'^[A-Za-z0-9]{6,16}$').hasMatch(reference.trim());
  }

  /// True when the reference is well-formed and every passenger row is
  /// valid (name + type + seat). An invalid ticket must never render as a
  /// normal ticket — screens show an error state instead.
  bool get isValid {
    if (!isValidReference(bookingReference)) return false;
    if (passengers.isEmpty ||
        passengers.length > PassengerFormState.maxPassengers) {
      return false;
    }
    for (final passenger in passengers) {
      if (!passenger.isValid) return false;
    }
    return true;
  }

  /// Plain JSON-safe serializer consumed by the later PDF step.
  ///
  /// Deferred `pdf`/`printing` packages were NOT added in this slice
  /// (zero-new-dependency rule); the coordinator's PDF step builds the
  /// downloadable file from this map. Every map carries the demo banner
  /// so generated files stay marked invalid for travel.
  Map<String, dynamic> toPrintMap() {
    return <String, dynamic>{
      'booking_reference': bookingReference.trim(),
      'demo_banner': demoBanner,
      'demo_note': demoNote,
      'trip': <String, String>{
        'train': trainLabel,
        'from': fromLabel,
        'to': toLabel,
        'depart': departLabel,
      },
      'passengers': <Map<String, String>>[
        for (final passenger in passengers)
          <String, String>{
            'name': passenger.name,
            'type': passenger.type?.label ?? 'Not set',
            'seat_code': passenger.seatCode,
          },
      ],
      'fare_bdt': Map<String, int>.of(fareBreakdown),
      'total_bdt': totalBdt,
    };
  }
}
