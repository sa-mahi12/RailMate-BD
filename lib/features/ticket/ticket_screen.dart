import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';

import '../../design/design.dart';
import '../../design/state/state.dart';
import 'ticket_data.dart';
import 'ticket_export.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _accentGreen = Color(0xFF1E9E6A);
const Color _dangerRed = Color(0xFFE5484D);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Ref-5 "E-Ticket" screen (packet A06 + F10): demonstration ticket only.
///
/// Renders a confirmed [ticket] snapshot passed in by the host — this screen
/// performs no Supabase calls and writes nothing. Shows the booking
/// reference with a real QR ([QrImageView] over [ticketQrPayload]), the full
/// passenger/seat list, the fare breakdown, and a download/share button that
/// builds the PDF from [buildDemoTicketPdf] (via [TicketData.toPrintMap])
/// and shares it with package:printing. Every state carries the
/// `DEMONSTRATION ONLY / invalid for travel` banner; no official logos and
/// no implied travel entitlement.
///
/// Invalid snapshots keep the error state: no QR, no download button.
///
/// V4 P17 polish (behavior unchanged): one-shot [FadeSlideIn] entrances per
/// section, a delayed QR reveal, a [StaggeredColumn] over the passenger
/// rows, the P26 [ErrorState] for invalid snapshots (same copy), and an
/// [AnimatedSwap] on the download button's busy state. The deterministic QR
/// payload, DEMONSTRATION ONLY wording and PDF contract are untouched.
class TicketScreen extends StatelessWidget {
  final TicketData ticket;

  const TicketScreen({super.key, required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryTeal,
        foregroundColor: Colors.white,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: const Text('E-Ticket'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FadeSlideIn(child: _DemoBanner()),
          const SizedBox(height: 12),
          if (!ticket.isValid)
            const FadeSlideIn(
              delay: Duration(milliseconds: 40),
              child: _InvalidTicketCard(),
            )
          else ...[
            FadeSlideIn(
              delay: const Duration(milliseconds: 40),
              child: _buildTicketCard(),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: _buildPassengersCard(),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: _buildFareCard(),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 160),
              child: _TicketDownloadButton(ticket: ticket),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketCard() {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: _accentGreen, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Booking confirmed (demo)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primaryTeal,
                        ),
                      ),
                      if (_routeLabel.isNotEmpty)
                        Text(
                          _routeLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The QR reveals slightly after the card settles, so the
            // reference feels issued rather than pasted.
            Center(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 220),
                child: _TicketQr(ticket: ticket),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Ref: ${ticket.bookingReference.trim()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Show this reference at demo review only.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _routeLabel {
    final from = ticket.fromLabel.trim();
    final to = ticket.toLabel.trim();
    if (from.isEmpty && to.isEmpty) return '';
    if (from.isEmpty) return to;
    if (to.isEmpty) return from;
    return '$from \u2192 $to';
  }

  Widget _buildPassengersCard() {
    final rows = <Widget>[];
    for (var i = 0; i < ticket.passengers.length; i++) {
      rows.add(_buildPassengerRow(i));
      if (i < ticket.passengers.length - 1) {
        rows.add(const Divider(height: 16));
      }
    }
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Passengers (${ticket.passengers.length})',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _primaryTeal,
              ),
            ),
            const SizedBox(height: 8),
            StaggeredColumn(children: rows),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengerRow(int index) {
    final passenger = ticket.passengers[index];
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: _primaryTeal.withValues(alpha: 0.1),
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: _primaryTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                passenger.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                passenger.type?.label ?? 'Type not set',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _primaryTeal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Seat ${passenger.seatCode}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFareCard() {
    final breakdown = ticket.fareBreakdown;
    String bdt(Object? value) => 'BDT ${value ?? 0}';
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fare breakdown',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _primaryTeal,
              ),
            ),
            const SizedBox(height: 8),
            _fareRow(
              'Base (${breakdown['passengerCount'] ?? ticket.passengers.length}'
              ' x ${bdt(breakdown['farePerSeat'])})',
              bdt(breakdown['baseFare']),
            ),
            _fareRow('Service charge', bdt(breakdown['serviceCharge'])),
            const Divider(height: 16),
            _fareRow('Total', bdt(ticket.totalBdt), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _fareRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? _primaryTeal : Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isTotal ? _primaryTeal : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line demonstration banner shown above every ticket state.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _dangerRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dangerRed.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _dangerRed, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              TicketData.demoBanner,
              style: TextStyle(
                color: _dangerRed,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state for malformed snapshots (bad reference or invalid rows).
///
/// Never renders a ticket-looking card: an invalid reference must not be
/// mistaken for travel entitlement.
class _InvalidTicketCard extends StatelessWidget {
  const _InvalidTicketCard();

  @override
  Widget build(BuildContext context) {
    return const ErrorState(
      icon: Icons.error_outline,
      title: 'Ticket unavailable',
      message:
          'The booking reference or passenger details are invalid. '
          'Go back and complete the booking first. '
          'DEMONSTRATION ONLY — invalid for travel.',
    );
  }
}

/// Real QR for a valid ticket (F10): encodes [ticketQrPayload].
///
/// Rendered only on the valid branch — invalid snapshots keep the error
/// state and never reach this widget. The demo banner sits directly above
/// the ticket card (see [_DemoBanner]) and the caption below restates the
/// demonstration-only nature adjacent to the code.
class _TicketQr extends StatelessWidget {
  final TicketData ticket;

  const _TicketQr({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final payload = ticketQrPayload(ticket);
    if (payload == null) {
      // Defensive: valid branch should always yield a payload; never show
      // a code-looking graphic for an invalid snapshot.
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 168,
            backgroundColor: Colors.white,
            errorStateBuilder: (context, error) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'QR unavailable for this demo reference.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Demo QR — encodes the reference only, not travel entitlement.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// Download/share button for the demonstration PDF (F10).
///
/// Builds the file from [buildDemoTicketPdf] (banner + note on every
/// page/footer, passenger table, fare breakdown, embedded QR) and shares it
/// via package:printing under an honest `railmate-demo-ticket-<ref>.pdf`
/// filename. Layout and share-sheet failures surface honestly with a retry
/// action; an invalid ticket never reaches this widget.
class _TicketDownloadButton extends StatefulWidget {
  final TicketData ticket;

  const _TicketDownloadButton({required this.ticket});

  @override
  State<_TicketDownloadButton> createState() => _TicketDownloadButtonState();
}

class _TicketDownloadButtonState extends State<_TicketDownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildDemoTicketPdf(widget.ticket);
      final filename = ticketPdfFilename(widget.ticket);
      final shared = await Printing.sharePdf(bytes: bytes, filename: filename);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? 'Shared $filename (DEMONSTRATION ONLY).'
                : 'Share dismissed — no file was sent.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not build the demo PDF: $e'),
          action: SnackBarAction(label: 'Retry', onPressed: _download),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwap(
              child: FilledButton.icon(
                key: ValueKey<bool>(_busy),
                onPressed: _busy ? null : _download,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_busy ? 'Building demo PDF…' : 'Download demo PDF'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${TicketData.demoBanner}. File: ${ticketPdfFilename(widget.ticket)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
