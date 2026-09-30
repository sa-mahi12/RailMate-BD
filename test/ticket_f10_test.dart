import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';
import 'package:railmate_bd/features/ticket/ticket_data.dart';
import 'package:railmate_bd/features/ticket/ticket_export.dart';

/// F10 hermetic tests: QR payload format, invalid gating, print-map banner,
/// and honest filename shape. PDF-byte goldens are NOT asserted (printing
/// needs platform channels); device rendering proof is F21 work.

TicketData makeTicket({
  String ref = 'BDR5F9K3',
  int totalBdt = 1440,
  List<Passenger> passengers = const [
    Passenger(name: 'Arif Hossain', type: PassengerType.adult, seatCode: 'A1'),
    Passenger(name: 'Mim Akter', type: PassengerType.child, seatCode: 'A2'),
  ],
}) => TicketData(
  bookingReference: ref,
  passengers: passengers,
  fareBreakdown: const {
    'passengerCount': 2,
    'farePerSeat': 700,
    'baseFare': 1400,
    'serviceCharge': 40,
    'total': 1440,
  },
  totalBdt: totalBdt,
  trainLabel: 'Jahanabad Express',
  fromLabel: 'Dhaka',
  toLabel: 'Khulna',
);

void main() {
  test('QR payload has the exact documented format', () {
    expect(ticketQrPayload(makeTicket()), 'RAILMATE-DEMO|BDR5F9K3|2|1440');
  });

  test('QR payload derives only from confirmed data', () {
    final oneWay = makeTicket(
      ref: 'XYZ12345',
      totalBdt: 740,
      passengers: const [
        Passenger(
          name: 'Nusrat Jahan',
          type: PassengerType.adult,
          seatCode: 'B3',
        ),
      ],
    );
    expect(ticketQrPayload(oneWay), 'RAILMATE-DEMO|XYZ12345|1|740');
  });

  test('invalid snapshots yield no QR payload', () {
    // Bad reference.
    expect(ticketQrPayload(makeTicket(ref: 'AB12')), isNull);
    expect(ticketQrPayload(makeTicket(ref: 'REF-123!')), isNull);
    // Invalid passenger row (empty name).
    expect(
      ticketQrPayload(
        makeTicket(
          passengers: const [
            Passenger(name: '', type: PassengerType.adult, seatCode: 'A1'),
          ],
        ),
      ),
      isNull,
    );
    // Empty passenger list.
    expect(ticketQrPayload(makeTicket(passengers: const [])), isNull);
  });

  test('print map carries demo banner and note', () {
    final map = makeTicket().toPrintMap();
    expect(map['demo_banner'], TicketData.demoBanner);
    expect(map['demo_banner'], contains('NOT VALID FOR TRAVEL'));
    expect(map['demo_note'], TicketData.demoNote);
  });

  test('PDF filename is honest and filesystem-safe', () {
    expect(
      ticketPdfFilename(makeTicket()),
      'railmate-demo-ticket-bdr5f9k3.pdf',
    );
    expect(
      ticketPdfFilenameForRef('  BDR5F9K3  '),
      'railmate-demo-ticket-bdr5f9k3.pdf',
    );
    expect(
      ticketPdfFilenameForRef('REF-123!'),
      'railmate-demo-ticket-ref123.pdf',
    );
    expect(
      ticketPdfFilename(makeTicket()),
      matches(RegExp(r'^railmate-demo-ticket-[a-z0-9]+\.pdf$')),
    );
  });

  test('PDF builder refuses invalid snapshots', () async {
    await expectLater(
      buildDemoTicketPdf(makeTicket(ref: 'bad!!')),
      throwsA(isA<StateError>()),
    );
  });

  test('PDF builder returns real PDF bytes for a valid ticket', () async {
    final bytes = await buildDemoTicketPdf(makeTicket());
    expect(bytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(bytes.take(5).toList()), '%PDF-');
  });
}
