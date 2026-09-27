import 'dart:convert';

/// Pure data model mirroring `public.stations` (demo seed rows in
/// `supabase/seed/01_demo_stations.sql`).
///
/// No Supabase/network dependency: plain map/JSON parsing only, so the
/// search UI (and later the ML ranking input) can use it without client
/// wiring, which stays in A01's lane.
class Station {
  final String id;
  final String code;
  final String name;
  final double? latitude;
  final double? longitude;

  const Station({
    required this.id,
    required this.code,
    required this.name,
    this.latitude,
    this.longitude,
  });

  /// PostgREST may decode `numeric(9,6)` as num or String; accept both.
  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  factory Station.fromMap(Map<String, dynamic> map) {
    return Station(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      latitude: _asDouble(map['latitude']),
      longitude: _asDouble(map['longitude']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'code': code,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Station.fromJson(String source) =>
      Station.fromMap(json.decode(source) as Map<String, dynamic>);

  String toJson() => json.encode(toMap());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Station &&
          id == other.id &&
          code == other.code &&
          name == other.name &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(id, code, name, latitude, longitude);
}
