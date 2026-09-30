import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ticket_data.dart';

/// F10 demonstration-ticket export helpers (pure Dart + package:pdf only).
///
/// QR payload format (documented contract, deterministic, no signatures):
///   `RAILMATE-DEMO|<bookingReference>|<passengerCount>|<totalBdt>`
/// where `<bookingReference>` is the trimmed confirmed reference,
/// `<passengerCount>` is the confirmed passenger count, and `<totalBdt>`
/// is the confirmed total fare in BDT. Derived ONLY from confirmed
/// [TicketData]; no invented signatures, no fake validation URLs.
///
/// Returns `null` for invalid snapshots ([TicketData.isValid] false) so
/// callers can gate QR rendering / PDF generation on validity.
String? ticketQrPayload(TicketData ticket) {
  if (!ticket.isValid) return null;
  final ref = ticket.bookingReference.trim();
  return 'RAILMATE-DEMO|$ref|${ticket.passengers.length}|${ticket.totalBdt}';
}

/// Honest PDF filename for a ticket snapshot.
/// e.g. `railmate-demo-ticket-bdr5f9k3.pdf`.
String ticketPdfFilename(TicketData ticket) =>
    ticketPdfFilenameForRef(ticket.bookingReference);

/// Filename helper over a raw reference (kept separate for testing).
String ticketPdfFilenameForRef(String reference) {
  final clean = reference.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  final safe = clean.isEmpty ? 'unknown' : clean;
  return 'railmate-demo-ticket-$safe.pdf';
}

/// Builds the downloadable demonstration-ticket PDF from [TicketData].
///
/// Source of truth is [TicketData.toPrintMap] plus [ticketQrPayload] for the
/// embedded QR. Every page carries [TicketData.demoBanner] in the header and
/// [TicketData.demoNote] in the footer. Throws [StateError] for invalid
/// snapshots so an unmarked or invalid file is never produced.
///
/// QR is embedded via `BarcodeWidget` (package:pdf QR barcode) encoding the
/// exact [ticketQrPayload] string — the same payload the screen QR shows.
Future<Uint8List> buildDemoTicketPdf(TicketData ticket) async {
  if (!ticket.isValid) {
    throw StateError('Refusing to build a PDF for an invalid ticket snapshot');
  }
  final payload = ticketQrPayload(ticket)!;
  final printMap = ticket.toPrintMap();

  final trip = (printMap['trip'] as Map).cast<String, String>();
  final passengers = ((printMap['passengers'] as List).cast<Map>())
      .cast<Map<String, String>>();
  final fare = (printMap['fare_bdt'] as Map).cast<String, int>();

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.red, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            TicketData.demoBanner,
            style: pw.TextStyle(
              color: PdfColors.red,
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              TicketData.demoNote,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Text(
          'RailMate BD — E-Ticket (demo)',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Ref: ${printMap['booking_reference']}',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _routeLabel(trip),
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        if (trip['depart']!.isNotEmpty)
          pw.Text(
            'Depart: ${trip['depart']}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        if (trip['train']!.isNotEmpty)
          pw.Text(
            'Train: ${trip['train']}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Column(
            children: [
              pw.BarcodeWidget(
                data: payload,
                barcode: pw.Barcode.qrCode(),
                width: 140,
                height: 140,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                payload,
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Passengers (${passengers.length})',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: const ['#', 'Name', 'Type', 'Seat'],
          data: [
            for (var i = 0; i < passengers.length; i++)
              [
                '${i + 1}',
                passengers[i]['name'] ?? '',
                passengers[i]['type'] ?? '',
                passengers[i]['seat_code'] ?? '',
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Fare breakdown (BDT)',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: const ['Item', 'Amount (BDT)'],
          data: [
            [
              'Base (${fare['passengerCount'] ?? passengers.length} x '
                  '${fare['farePerSeat'] ?? 0})',
              '${fare['baseFare'] ?? 0}',
            ],
            ['Service charge', '${fare['serviceCharge'] ?? 0}'],
            ['Total', '${printMap['total_bdt']}'],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Show this reference at demo review only. '
          '${TicketData.demoNote}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );

  return doc.save();
}

String _routeLabel(Map<String, String> trip) {
  final from = (trip['from'] ?? '').trim();
  final to = (trip['to'] ?? '').trim();
  if (from.isEmpty && to.isEmpty) return '';
  if (from.isEmpty) return to;
  if (to.isEmpty) return from;
  return '$from → $to';
}
