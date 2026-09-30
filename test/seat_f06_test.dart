import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_state.dart';
import 'package:railmate_bd/features/search/models/trip_seat.dart';
import 'package:railmate_bd/features/search/seat_inventory.dart';

/// F06 hermetic tests: real `demoReserved` model field + pure row mapping +
/// revalidate-drops-held.
///
/// NOTE for coordinator: [fetchTripSeats] takes a real SupabaseClient, so
/// the query path itself cannot be unit-tested hermetically — it is covered
/// by the pure [mapSeatRow] tests below (same function the live query path
/// uses) plus coordinator-verified live runs (`flutter test
/// test/seat_f06_test.dart` for this file; F21 device run for held-seat
/// display proof).

TripSeat seat(String code, {String? bookingId, bool demoReserved = false}) =>
    TripSeat(
      id: 't1-$code',
      tripId: 't1',
      seatCode: code,
      bookingId: bookingId,
      demoReserved: demoReserved,
    );

void main() {
  group('TripSeat.demoReserved parsing', () {
    test('parses demo_reserved=true', () {
      final seat = TripSeat.fromMap(const {
        'id': 's1',
        'trip_id': 't1',
        'seat_code': 'A1',
        'booking_id': null,
        'demo_reserved': true,
      });
      expect(seat.demoReserved, isTrue);
      expect(seat.bookingId, isNull);
    });

    test('parses demo_reserved=false', () {
      final seat = TripSeat.fromMap(const {
        'id': 's1',
        'trip_id': 't1',
        'seat_code': 'A1',
        'booking_id': null,
        'demo_reserved': false,
      });
      expect(seat.demoReserved, isFalse);
    });

    test('BACKWARD COMPAT: missing column parses as false', () {
      final seat = TripSeat.fromMap(const {
        'id': 's1',
        'trip_id': 't1',
        'seat_code': 'A1',
        'booking_id': null,
      });
      expect(seat.demoReserved, isFalse);
      expect(seat.isAvailable, isTrue);
    });

    test('non-boolean demo_reserved is not treated as held', () {
      for (final value in [1, 'true', 't']) {
        final seat = TripSeat.fromMap({
          'id': 's1',
          'trip_id': 't1',
          'seat_code': 'A1',
          'booking_id': null,
          'demo_reserved': value,
        });
        expect(seat.demoReserved, isFalse, reason: 'value: $value');
      }
    });

    test('toMap includes demo_reserved; json round-trips', () {
      final held = seat('A1', demoReserved: true);
      expect(held.toMap()['demo_reserved'], isTrue);
      expect(TripSeat.fromJson(held.toJson()), held);

      final free = seat('A2');
      expect(free.toMap()['demo_reserved'], isFalse);
      expect(TripSeat.fromJson(free.toJson()), free);
    });

    test('equality/hashCode distinguish demoReserved', () {
      expect(seat('A1'), seat('A1'));
      expect(seat('A1').hashCode, seat('A1').hashCode);
      expect(seat('A1', demoReserved: true), isNot(seat('A1')));
    });
  });

  group('isAvailable matrix', () {
    test('free: bookingId null + not held -> available', () {
      expect(seat('A1').isAvailable, isTrue);
    });

    test('held: bookingId null + demoReserved -> UNAVAILABLE', () {
      expect(seat('A1', demoReserved: true).isAvailable, isFalse);
    });

    test('booked: bookingId set + not held -> UNAVAILABLE', () {
      expect(seat('A1', bookingId: 'bk-1').isAvailable, isFalse);
    });

    test('both: bookingId set + held -> UNAVAILABLE', () {
      expect(
        seat('A1', bookingId: 'bk-1', demoReserved: true).isAvailable,
        isFalse,
      );
    });

    test('isDemoHeld only for held-but-unbooked rows', () {
      expect(seat('A1', demoReserved: true).isDemoHeld, isTrue);
      expect(seat('A1').isDemoHeld, isFalse);
      expect(seat('A1', bookingId: 'bk-1').isDemoHeld, isFalse);
      expect(
        seat('A1', bookingId: 'bk-1', demoReserved: true).isDemoHeld,
        isFalse,
      );
    });
  });

  group('mapSeatRow (pure live-row mapping)', () {
    test('demo-held live row: NO booking_id synthesis, real flag through', () {
      final mapped = mapSeatRow(const {
        'id': 's1',
        'trip_id': 't1',
        'seat_code': 'A1',
        'booking_id': null,
        'demo_reserved': true,
      });
      expect(
        mapped.bookingId,
        isNull,
        reason: 'F06 removed the demo-reserved bookingId hack',
      );
      expect(mapped.demoReserved, isTrue);
      expect(mapped.isAvailable, isFalse);
    });

    test('free live row stays available', () {
      final mapped = mapSeatRow(const {
        'id': 's2',
        'trip_id': 't1',
        'seat_code': 'A2',
        'booking_id': null,
        'demo_reserved': false,
      });
      expect(mapped.isAvailable, isTrue);
    });

    test('booked live row stays unavailable with booking id intact', () {
      final mapped = mapSeatRow(const {
        'id': 's3',
        'trip_id': 't1',
        'seat_code': 'A3',
        'booking_id': 'bk-9',
        'demo_reserved': false,
      });
      expect(mapped.isAvailable, isFalse);
      expect(mapped.bookingId, 'bk-9');
    });

    test('legacy row without the column still parses (available)', () {
      final mapped = mapSeatRow(const {
        'id': 's4',
        'trip_id': 't1',
        'seat_code': 'A4',
        'booking_id': null,
      });
      expect(mapped.demoReserved, isFalse);
      expect(mapped.isAvailable, isTrue);
    });
  });

  group('SeatSelectionState with demo-held seats', () {
    test('held seats: isBooked/canSelect/toggle treat like booked', () async {
      final state = SeatSelectionState(
        tripId: 't1',
        fetchSeats: (_) async => [
          seat('A1'),
          seat('A2', demoReserved: true),
          seat('A3', bookingId: 'bk-1'),
        ],
      );
      await state.load();
      expect(state.status, SeatSelectionStatus.loaded);

      expect(state.isBooked('A2'), isTrue);
      expect(state.canSelect('A2'), isFalse);
      expect(state.toggle('A2'), isFalse);
      expect(state.selectedSeatCodes, isEmpty);

      // Free seat still selectable alongside held/booked ones.
      expect(state.toggle('A1'), isTrue);
      expect(state.selectedSeatCodes, ['A1']);
    });

    test(
      'revalidate drops seats that became demo-held between loads',
      () async {
        var held = <String>{};
        final state = SeatSelectionState(
          tripId: 't1',
          fetchSeats: (_) async => [
            seat('B1'),
            seat('B2', demoReserved: held.contains('B2')),
            seat('B3'),
          ],
        );
        await state.load();
        expect(state.toggle('B1'), isTrue);
        expect(state.toggle('B2'), isTrue);
        expect(state.selectedSeatCodes, ['B1', 'B2']);

        // Server holds B2 for the demo horizon between loads.
        held = {'B2'};
        final dropped = await state.revalidate();

        expect(dropped, ['B2']);
        expect(state.selectedSeatCodes, ['B1']);
        expect(state.seatByCode('B2')!.demoReserved, isTrue);
        expect(state.seatByCode('B2')!.bookingId, isNull);
        expect(state.isBooked('B2'), isTrue);
      },
    );
  });
}
