import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/features/ticket/ticket_data.dart';

/// F07 hermetic tests: booking-submit payload builder, response parser,
/// display-reference derivation and failure messages.
///
/// The `SupabaseClient.functions.invoke` network path itself is NOT unit
/// tested here — it is proven live by the coordinator (deployed Edge
/// smoke: unauthenticated POST -> 401; authenticated booking -> F08/F20).
/// These tests pin the pure contract so a silent shape drift fails loudly.
void main() {
  group('buildBookTripBody (Edge contract shape)', () {
    test('shapes trip/request/passengers/seats/simulateSuccess', () {
      final body = buildBookTripBody(
        tripId: '11111111-1111-4111-8111-111111111111',
        requestId: '22222222-2222-4222-8222-222222222222',
        passengerNames: const ['Alice Rahman', 'Bo'],
        seatCodes: const ['A1', 'A2'],
        simulateSuccess: true,
      );
      expect(body['trip_id'], '11111111-1111-4111-8111-111111111111');
      expect(body['request_id'], '22222222-2222-4222-8222-222222222222');
      expect(body['passengers'], [
        {'name': 'Alice Rahman'},
        {'name': 'Bo'},
      ]);
      expect(body['seat_codes'], ['A1', 'A2']);
      expect(body['simulateSuccess'], isTrue);
    });

    test('trims passenger names and copies seat codes', () {
      final seats = ['B3'];
      final body = buildBookTripBody(
        tripId: 't',
        requestId: 'r',
        passengerNames: const ['  Cara  '],
        seatCodes: seats,
        simulateSuccess: false,
      );
      expect(body['passengers'], [
        {'name': 'Cara'},
      ]);
      expect(body['simulateSuccess'], isFalse);
      // Copy, not alias: mutating the source list must not affect the body.
      seats.add('B4');
      expect(body['seat_codes'], ['B3']);
    });
  });

  group('parseBookTripResponse', () {
    test('CONFIRMED returns the server-issued booking id', () {
      expect(
        parseBookTripResponse(const <String, dynamic>{
          'booking_id': '33333333-3333-4333-8333-333333333333',
          'status': 'CONFIRMED',
        }),
        '33333333-3333-4333-8333-333333333333',
      );
    });

    test('server codes throw with the genuine code', () {
      for (final code in [
        'SEAT_UNAVAILABLE',
        'TRIP_UNAVAILABLE',
        'IDEMPOTENCY_CONFLICT',
        'INVALID_REQUEST',
        'UNAUTHORIZED',
      ]) {
        expect(
          () => parseBookTripResponse(<String, dynamic>{'code': code}),
          throwsA(
            isA<BookingSubmitException>().having((e) => e.code, 'code', code),
          ),
          reason: code,
        );
      }
    });

    test('failed simulation status throws without synthesising an id', () {
      expect(
        () => parseBookTripResponse(const <String, dynamic>{
          'status': 'PAYMENT_SIMULATION_FAILED',
        }),
        throwsA(
          isA<BookingSubmitException>().having(
            (e) => e.code,
            'code',
            'PAYMENT_SIMULATION_FAILED',
          ),
        ),
      );
    });

    test('garbage response throws BOOKING_FAILED', () {
      expect(
        () => parseBookTripResponse(const <String, dynamic>{}),
        throwsA(
          isA<BookingSubmitException>().having(
            (e) => e.code,
            'code',
            'BOOKING_FAILED',
          ),
        ),
      );
    });
  });

  group('displayReferenceForBookingId', () {
    test('derives an 8-char reference valid for TicketData', () {
      final ref = displayReferenceForBookingId(
        'a1b2c3d4-e5f6-4789-8123-456789abcdef',
      );
      expect(ref, 'A1B2C3D4');
      expect(TicketData.isValidReference(ref), isTrue);
    });

    test('rejects garbage instead of fabricating', () {
      expect(() => displayReferenceForBookingId(''), throwsArgumentError);
      expect(() => displayReferenceForBookingId('xyz'), throwsArgumentError);
    });
  });

  group('BookingSubmitException.message', () {
    test('never claims a booking was created', () {
      for (final code in [
        'SEAT_UNAVAILABLE',
        'TRIP_UNAVAILABLE',
        'IDEMPOTENCY_CONFLICT',
        'BOOKING_FAILED',
      ]) {
        final message = BookingSubmitException(code).message;
        expect(
          message,
          contains('booking was created'),
          reason: '$code must disclaim booking creation',
        );
        expect(
          message,
          contains('No '),
          reason: '$code must negate the booking claim',
        );
        expect(message, isNot(contains('confirmed')));
      }
    });
  });
}
