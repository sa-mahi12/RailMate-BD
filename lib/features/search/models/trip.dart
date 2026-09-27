import 'dart:convert';

/// Pure data model mirroring `public.trips` (demo seed rows in
/// `supabase/seed/02_demo_trips_seats.sql`).
///
/// All demo rows carry a `DEMO ` train-name prefix and must be rendered
/// with a DEMONSTRATION ONLY notice. No Supabase/network dependency.
class Trip {
  final String id;
  final String trainName;
  final String originStationId;
  final String destinationStationId;
  final DateTime departureAt;
  final DateTime arrivalAt;
  final int fareBdt;
  final bool active;

  const Trip({
    required this.id,
    required this.trainName,
    required this.originStationId,
    required this.destinationStationId,
    required this.departureAt,
    required this.arrivalAt,
    required this.fareBdt,
    required this.active,
  });

  /// True when this row was produced by the B01 demo seed.
  bool get isDemo => trainName.startsWith('DEMO ');

  static DateTime _asDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value as String);
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value);
    throw FormatException('Cannot parse fare_bdt from $value');
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    throw FormatException('Cannot parse active from $value');
  }

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      id: map['id'] as String,
      trainName: map['train_name'] as String,
      originStationId: map['origin_station_id'] as String,
      destinationStationId: map['destination_station_id'] as String,
      departureAt: _asDateTime(map['departure_at']),
      arrivalAt: _asDateTime(map['arrival_at']),
      fareBdt: _asInt(map['fare_bdt']),
      active: _asBool(map['active']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'train_name': trainName,
      'origin_station_id': originStationId,
      'destination_station_id': destinationStationId,
      'departure_at': departureAt.toIso8601String(),
      'arrival_at': arrivalAt.toIso8601String(),
      'fare_bdt': fareBdt,
      'active': active,
    };
  }

  factory Trip.fromJson(String source) =>
      Trip.fromMap(json.decode(source) as Map<String, dynamic>);

  String toJson() => json.encode(toMap());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Trip &&
          id == other.id &&
          trainName == other.trainName &&
          originStationId == other.originStationId &&
          destinationStationId == other.destinationStationId &&
          departureAt.isAtSameMomentAs(other.departureAt) &&
          arrivalAt.isAtSameMomentAs(other.arrivalAt) &&
          fareBdt == other.fareBdt &&
          active == other.active;

  @override
  int get hashCode => Object.hash(
    id,
    trainName,
    originStationId,
    destinationStationId,
    departureAt,
    arrivalAt,
    fareBdt,
    active,
  );
}
