// ignore_for_file: prefer_initializing_formals
// Reason: constructor keeps public parameter names (contactMobile,
// contactEmail); initializing formals would force private parameter names
// that callers outside this library could not use.
import 'package:flutter/foundation.dart';

import 'passenger.dart';

/// Form state for packet B05 (R-06): one passenger per selected seat.
///
/// The host (booking flow) creates and owns this object and passes it into
/// [passenger_details_screen] and [booking_review_screen]; the screens never
/// create, replace or dispose it, so typed data survives tab switches and
/// back navigation. [TextEditingController]s stay widget-local; only plain
/// strings live here.
///
/// Stored data is name + Adult/Child type + assigned seat per passenger plus
/// one shared booking contact (mobile + optional email). No government ID
/// and no payment fields (packet stop condition).
class PassengerFormState extends ChangeNotifier {
  /// Product contract: a booking holds 1–4 passengers/seats.
  static const int minPassengers = 1;
  static const int maxPassengers = 4;

  /// Flat service charge in BDT added once per booking (ref-4: BDT 40).
  static const int serviceChargeBdt = 40;

  /// Per-seat fare in BDT for the selected trip.
  final int fareBdt;

  final List<Passenger> _passengers;

  String _contactMobile;
  String _contactEmail;

  /// Creates state sized to [seatCodes] (1–4 distinct codes, sorted copy).
  ///
  /// Existing names/types are empty/`null` (invalid until the user types).
  /// Throws [ArgumentError] when [seatCodes] is empty or exceeds
  /// [maxPassengers], or when [fareBdt] is negative.
  PassengerFormState({
    required List<String> seatCodes,
    required this.fareBdt,
    String contactMobile = '',
    String contactEmail = '',
  }) : _passengers = <Passenger>[
         for (final code in (List<String>.of(seatCodes)..sort()))
           Passenger(name: '', type: null, seatCode: code),
       ],
       _contactMobile = contactMobile,
       _contactEmail = contactEmail {
    if (fareBdt < 0) {
      throw ArgumentError.value(fareBdt, 'fareBdt', 'Must be >= 0');
    }
    if (seatCodes.isEmpty || seatCodes.length > maxPassengers) {
      throw ArgumentError.value(
        seatCodes.length,
        'seatCodes',
        'Must hold 1-$maxPassengers seats',
      );
    }
    if (seatCodes.toSet().length != seatCodes.length) {
      throw ArgumentError.value(
        seatCodes,
        'seatCodes',
        'Seat codes must be distinct',
      );
    }
  }

  /// Passengers in seat-code order; unmodifiable view.
  List<Passenger> get passengers => List<Passenger>.unmodifiable(_passengers);

  /// Assigned seat codes in order (mirrors the seat-selection shape).
  List<String> get seatCodes =>
      List<String>.unmodifiable(_passengers.map((p) => p.seatCode));

  /// Number of passengers (== number of selected seats).
  int get count => _passengers.length;

  /// Shared booking contact: mobile is required, email optional.
  String get contactMobile => _contactMobile;
  String get contactEmail => _contactEmail;

  /// Mobile is required: 6–15 chars of digits, spaces, `+` or `-`.
  static String? validateContactMobile(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter mobile number';
    if (!RegExp(r'^[+0-9][0-9 +\-]{5,14}$').hasMatch(trimmed)) {
      return 'Enter a valid mobile number';
    }
    return null;
  }

  /// Email is optional: empty passes; otherwise must look like an address.
  static String? validateContactEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Contact-level error, if any.
  String? get contactError =>
      validateContactMobile(_contactMobile) ??
      validateContactEmail(_contactEmail);

  /// Per-passenger validation error for [index], else `null`.
  String? errorFor(int index) => _passengers[index].validate();

  /// True when every passenger is valid and the contact is valid.
  bool get isValid {
    if (_passengers.isEmpty || _passengers.length > maxPassengers) {
      return false;
    }
    for (final passenger in _passengers) {
      if (!passenger.isValid) return false;
    }
    return contactError == null;
  }

  /// Base fare: [fareBdt] × passenger count.
  int get baseFareBdt => fareBdt * _passengers.length;

  /// Total payable: base + flat service charge.
  int get totalBdt => baseFareBdt + serviceChargeBdt;

  /// Fare numbers for the review screen, all in BDT:
  /// `passengerCount`, `farePerSeat`, `baseFare`, `serviceCharge`, `total`.
  Map<String, int> get fareBreakdown => <String, int>{
    'passengerCount': _passengers.length,
    'farePerSeat': fareBdt,
    'baseFare': baseFareBdt,
    'serviceCharge': serviceChargeBdt,
    'total': totalBdt,
  };

  /// Updates the name of passenger [index] (trims only for validation).
  void updateName(int index, String name) {
    _checkIndex(index);
    if (_passengers[index].name == name) return;
    _passengers[index] = _passengers[index].copyWith(name: name);
    notifyListeners();
  }

  /// Updates the type of passenger [index].
  void updateType(int index, PassengerType? type) {
    _checkIndex(index);
    final current = _passengers[index];
    if (current.type == type) return;
    _passengers[index] = type == null
        ? current.copyWith(clearType: true)
        : current.copyWith(type: type);
    notifyListeners();
  }

  /// Updates the shared contact mobile.
  void setContactMobile(String value) {
    if (_contactMobile == value) return;
    _contactMobile = value;
    notifyListeners();
  }

  /// Updates the shared contact email (optional).
  void setContactEmail(String value) {
    if (_contactEmail == value) return;
    _contactEmail = value;
    notifyListeners();
  }

  /// Re-targets the form at a new seat selection (1–4 distinct codes),
  /// preserving already typed name/type rows matched by seat code and
  /// appending blank rows for new codes. Keeps back-navigation and
  /// seat-edit flows loss-free.
  void retargetSeats(List<String> seatCodes) {
    if (seatCodes.isEmpty || seatCodes.length > maxPassengers) {
      throw ArgumentError.value(
        seatCodes.length,
        'seatCodes',
        'Must hold 1-$maxPassengers seats',
      );
    }
    if (seatCodes.toSet().length != seatCodes.length) {
      throw ArgumentError.value(
        seatCodes,
        'seatCodes',
        'Seat codes must be distinct',
      );
    }
    final bySeat = <String, Passenger>{
      for (final passenger in _passengers) passenger.seatCode: passenger,
    };
    final sorted = List<String>.of(seatCodes)..sort();
    _passengers
      ..clear()
      ..addAll(
        sorted.map(
          (code) =>
              bySeat[code] ?? Passenger(name: '', type: null, seatCode: code),
        ),
      );
    notifyListeners();
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= _passengers.length) {
      throw RangeError.index(index, _passengers, 'index');
    }
  }
}
