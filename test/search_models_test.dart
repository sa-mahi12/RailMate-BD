import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/models/trip_seat.dart';

void main() {
  test('Station parses numeric coords given as String', () {
    final s = Station.fromMap(const {
      'id': '11111111-1111-4111-8111-111111111111',
      'code': 'DAC',
      'name': 'Dhaka',
      'latitude': '23.810300',
      'longitude': 90.4125,
    });
    expect(s.latitude, 23.8103);
    expect(s.toMap()['code'], 'DAC');
    expect(Station.fromJson(s.toJson()), s);
  });

  test('Trip parses seed row and flags demo', () {
    final t = Trip.fromMap(const {
      'id': 'a1a1a1a1-1111-4111-8111-aaaaaaaaaaaa',
      'train_name': 'DEMO Trial Runner 101',
      'origin_station_id': '11111111-1111-4111-8111-111111111111',
      'destination_station_id': '22222222-2222-4222-8222-222222222222',
      'departure_at': '2026-10-15T07:00:00+06:00',
      'arrival_at': '2026-10-15T12:30:00+06:00',
      'fare_bdt': 450,
      'active': true,
    });
    expect(t.isDemo, isTrue);
    expect(Trip.fromJson(t.toJson()), t);
  });

  test('TripSeat null booking means available', () {
    final seat = TripSeat.fromMap(const {
      'id': 'x',
      'trip_id': 'y',
      'seat_code': 'A-01',
      'booking_id': null,
    });
    expect(seat.isAvailable, isTrue);
  });

  test('Trip rejects non-numeric fare', () {
    expect(
      () => Trip.fromMap(const {
        'id': 'a1a1a1a1-1111-4111-8111-aaaaaaaaaaaa',
        'train_name': 'DEMO Trial Runner 101',
        'origin_station_id': '11111111-1111-4111-8111-111111111111',
        'destination_station_id': '22222222-2222-4222-8222-222222222222',
        'departure_at': '2026-10-15T07:00:00+06:00',
        'arrival_at': '2026-10-15T12:30:00+06:00',
        'fare_bdt': 'free',
        'active': true,
      }),
      throwsFormatException,
    );
  });
}
