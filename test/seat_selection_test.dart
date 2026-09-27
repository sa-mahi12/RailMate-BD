import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_state.dart';
import 'package:railmate_bd/features/search/models/trip_seat.dart';

List<TripSeat> seatsOf(String tripId, List<String> booked) => [
  for (var r = 0; r < 5; r++)
    for (var c = 1; c <= 5; c++)
      TripSeat(
        id: '$tripId-${'ABCDE'[r]}$c',
        tripId: tripId,
        seatCode: '${'ABCDE'[r]}$c',
        bookingId: booked.contains('${'ABCDE'[r]}$c') ? 'bk-1' : null,
      ),
];

void main() {
  test('load populates seats and starts unselected', () async {
    final s = SeatSelectionState(
      tripId: 't1',
      fetchSeats: (_) async => seatsOf('t1', ['A2']),
    );
    await s.load();
    expect(s.status, SeatSelectionStatus.loaded);
    expect(s.seats.length, 25);
    expect(s.selectedSeatCodes, isEmpty);
    expect(s.loadedAt, isNotNull);
  });

  test('NEGATIVE: cannot select a fifth seat', () async {
    final s = SeatSelectionState(
      tripId: 't1',
      fetchSeats: (_) async => seatsOf('t1', []),
    );
    await s.load();
    expect(s.toggle('A1'), isTrue);
    expect(s.toggle('A2'), isTrue);
    expect(s.toggle('A3'), isTrue);
    expect(s.toggle('A4'), isTrue);
    expect(s.toggle('A5'), isFalse); // rejected
    expect(s.selectedSeatCodes, ['A1', 'A2', 'A3', 'A4']);
  });

  test('NEGATIVE: booked seat toggle ignored and canSelect false', () async {
    final s = SeatSelectionState(
      tripId: 't1',
      fetchSeats: (_) async => seatsOf('t1', ['B3']),
    );
    await s.load();
    expect(s.isBooked('B3'), isTrue);
    expect(s.canSelect('B3'), isFalse);
    expect(s.toggle('B3'), isFalse);
    expect(s.selectedSeatCodes, isEmpty);
  });

  test('NEGATIVE: revalidate drops seats booked since selection', () async {
    var booked = <String>[];
    final s = SeatSelectionState(
      tripId: 't1',
      fetchSeats: (_) async => seatsOf('t1', booked),
    );
    await s.load();
    s.toggle('C1');
    s.toggle('C2');
    booked = ['C2']; // another passenger booked C2 server-side
    final dropped = await s.revalidate();
    expect(dropped, ['C2']);
    expect(s.selectedSeatCodes, ['C1']);
  });

  test('toggle removes; load error surfaces message', () async {
    final s = SeatSelectionState(
      tripId: 't1',
      fetchSeats: (_) async => seatsOf('t1', []),
    );
    await s.load();
    s.toggle('D1');
    expect(s.toggle('D1'), isTrue);
    expect(s.selectedSeatCodes, isEmpty);
    final e = SeatSelectionState(
      tripId: 't1',
      fetchSeats: (_) async => throw Exception('offline'),
    );
    await e.load();
    expect(e.status, SeatSelectionStatus.error);
    expect(e.errorMessage, contains('offline'));
  });
}
