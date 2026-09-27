/// Pure passenger model for packet B05 (R-06).
///
/// One [Passenger] is assigned to exactly one selected seat. Name plus
/// [PassengerType] (Adult/Child) plus the assigned [seatCode] are the only
/// stored fields — deliberately no government ID and no payment fields
/// (stop condition per packet B05).
///
/// Zero dependencies: no Flutter, no Supabase, no network. Validation is
/// synchronous and unit-testable so tests can live outside the widget tree.
enum PassengerType { adult, child }

/// Display labels for [PassengerType] matching ref-4 wording.
extension PassengerTypeLabel on PassengerType {
  /// e.g. `Adult (A)` / `Child (C)`.
  String get label {
    switch (this) {
      case PassengerType.adult:
        return 'Adult (A)';
      case PassengerType.child:
        return 'Child (C)';
    }
  }

  /// Short seat-map code: `A` for adult, `C` for child.
  String get shortCode {
    switch (this) {
      case PassengerType.adult:
        return 'A';
      case PassengerType.child:
        return 'C';
    }
  }
}

/// One passenger bound to one seat.
///
/// [type] is nullable so a freshly created row can represent the
/// "nothing selected yet" form state; [validate] then reports the missing
/// type instead of the model becoming unconstructible.
class Passenger {
  /// Passenger full name, trimmed before validation.
  final String name;

  /// Adult or child; `null` means "not chosen yet" (invalid).
  final PassengerType? type;

  /// Assigned seat code (e.g. `C1`). Exactly one passenger per seat.
  final String seatCode;

  const Passenger({
    required this.name,
    required this.type,
    required this.seatCode,
  });

  /// Minimum/maximum trimmed name length (packet B05 contract).
  static const int minNameLength = 2;
  static const int maxNameLength = 50;

  /// Returns an error string when [name] is invalid, else `null`.
  static String? validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter passenger name';
    if (trimmed.length < minNameLength) {
      return 'Name must be at least $minNameLength characters';
    }
    if (trimmed.length > maxNameLength) {
      return 'Name must be at most $maxNameLength characters';
    }
    return null;
  }

  /// Returns an error string when no passenger [type] is chosen.
  static String? validateType(PassengerType? type) {
    if (type == null) return 'Select passenger type';
    return null;
  }

  /// Returns an error string when [seatCode] is missing.
  static String? validateSeatCode(String seatCode) {
    if (seatCode.trim().isEmpty) return 'Seat is required';
    return null;
  }

  /// First validation failure across name, type and seat, else `null`.
  String? validate() {
    return validateName(name) ??
        validateType(type) ??
        validateSeatCode(seatCode);
  }

  /// True when [validate] reports no error.
  bool get isValid => validate() == null;

  /// Copy with optional overrides; keeps the model immutable for the form.
  Passenger copyWith({
    String? name,
    PassengerType? type,
    bool clearType = false,
    String? seatCode,
  }) {
    return Passenger(
      name: name ?? this.name,
      type: clearType ? null : (type ?? this.type),
      seatCode: seatCode ?? this.seatCode,
    );
  }

  /// Plain-map form for the later booking lane (no ID/payment keys).
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'type': type?.name,
      'seat_code': seatCode,
    };
  }

  /// Inverse of [toMap]; unknown type strings decode to `null` (invalid
  /// rather than throwing, so review can surface the error).
  factory Passenger.fromMap(Map<String, dynamic> map) {
    final rawType = map['type'] as String?;
    PassengerType? type;
    if (rawType != null) {
      for (final candidate in PassengerType.values) {
        if (candidate.name == rawType) type = candidate;
      }
    }
    return Passenger(
      name: (map['name'] ?? '') as String,
      type: type,
      seatCode: (map['seat_code'] ?? '') as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Passenger &&
          name == other.name &&
          type == other.type &&
          seatCode == other.seatCode;

  @override
  int get hashCode => Object.hash(name, type, seatCode);

  @override
  String toString() =>
      'Passenger(name: $name, type: ${type?.name}, seatCode: $seatCode)';
}
