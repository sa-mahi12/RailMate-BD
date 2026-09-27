import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';
import 'package:railmate_bd/features/ticket/ticket_data.dart';

TicketData makeTicket({String ref = 'BDR5F9K3'}) => TicketData(
  bookingReference: ref,
  passengers: const [
    Passenger(name: 'Arif Hossain', type: PassengerType.adult, seatCode: 'A1'),
    Passenger(name: 'Mim Akter', type: PassengerType.child, seatCode: 'A2'),
  ],
  fareBreakdown: const {
    'passengerCount': 2,
    'farePerSeat': 700,
    'baseFare': 1400,
    'serviceCharge': 40,
    'total': 1440,
  },
  totalBdt: 1440,
  trainLabel: 'Jahanabad Express',
  fromLabel: 'Dhaka',
  toLabel: 'Khulna',
);

void main() {
  test('all passengers/seats shown with DEMO banner in print map', () {
    final map = makeTicket().toPrintMap();
    expect(map['demo_banner'], contains('NOT VALID FOR TRAVEL'));
    expect((map['passengers'] as List).length, 2);
    expect((map['passengers'] as List)[1]['seat_code'], 'A2');
    expect(map['total_bdt'], 1440);
  });
  test('invalid-reference negative', () {
    for (final bad in ['', 'AB12', 'REF-123!', 'waytoolongreference123']) {
      expect(makeTicket(ref: bad).isValid, isFalse);
    }
    expect(makeTicket().isValid, isTrue);
  });
}
