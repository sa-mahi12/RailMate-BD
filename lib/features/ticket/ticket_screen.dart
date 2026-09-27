import 'package:flutter/material.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';

import 'ticket_data.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _accentGreen = Color(0xFF1E9E6A);
const Color _dangerRed = Color(0xFFE5484D);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Ref-5 "E-Ticket" screen (packet A06): demonstration ticket only.
///
/// Renders a confirmed [ticket] snapshot passed in by the host — this screen
/// performs no Supabase calls and writes nothing. Shows the booking
/// reference with a QR-style placeholder grid, the full passenger/seat
/// list, and the fare breakdown. Every state carries the
/// `DEMONSTRATION ONLY / invalid for travel` banner; no official logos and
/// no implied travel entitlement.
///
/// QR note: no `qr_flutter` (or `pdf`/`printing`) package is vendored in
/// `pubspec.yaml`, and this slice adds zero new dependencies per the packet
/// contract — so the reference is shown as text plus a deterministic
/// [_QrStub] grid placeholder. A later step can swap [_QrStub] for a real
/// `qr_flutter` widget encoding [TicketData.bookingReference], and build
/// the downloadable PDF from [TicketData.toPrintMap].
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
          const _DemoBanner(),
          const SizedBox(height: 12),
          if (!ticket.isValid)
            const _InvalidTicketCard()
          else ...[
            _buildTicketCard(),
            const SizedBox(height: 12),
            _buildPassengersCard(),
            const SizedBox(height: 12),
            _buildFareCard(),
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
            Center(child: _QrStub(reference: ticket.bookingReference)),
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
            for (var i = 0; i < ticket.passengers.length; i++) ...[
              _buildPassengerRow(i),
              if (i < ticket.passengers.length - 1) const Divider(height: 16),
            ],
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
    return const Card(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: _dangerRed, size: 40),
            SizedBox(height: 8),
            Text(
              'Ticket unavailable',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'The booking reference or passenger details are invalid. '
              'Go back and complete the booking first. '
              'DEMONSTRATION ONLY \u2014 invalid for travel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deterministic QR-style placeholder grid for the booking reference.
///
/// Stand-in until the coordinator approves a real `qr_flutter` dependency:
/// encodes nothing scannable — it only visualizes the reference alongside
/// the reference text. The cell pattern derives from the reference's
/// hash code so each booking looks distinct while staying stable across
/// rebuilds.
class _QrStub extends StatelessWidget {
  final String reference;

  const _QrStub({required this.reference});

  @override
  Widget build(BuildContext context) {
    const cells = 21;
    final seed = reference.trim().hashCode;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: SizedBox(
        width: 168,
        height: 168,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cells,
          ),
          itemCount: cells * cells,
          itemBuilder: (context, index) {
            final row = index ~/ cells;
            final col = index % cells;
            final finder = _isFinderPattern(row, col, cells);
            final filled = finder || (seed + row * 31 + col * 17) % 3 == 0;
            return Container(
              margin: const EdgeInsets.all(0.5),
              color: filled ? Colors.black87 : Colors.white,
            );
          },
        ),
      ),
    );
  }

  bool _isFinderPattern(int row, int col, int size) {
    bool inSquare(int r0, int c0) =>
        row >= r0 && row < r0 + 7 && col >= c0 && col < c0 + 7;
    if (!inSquare(0, 0) && !inSquare(0, size - 7) && !inSquare(size - 7, 0)) {
      return false;
    }
    final r = row % size;
    final c = col % size;
    final lr = r < 7 ? r : r - (size - 7);
    final lc = c < 7 ? c : c - (size - 7);
    final outer = lr == 0 || lr == 6 || lc == 0 || lc == 6;
    final inner = lr >= 2 && lr <= 4 && lc >= 2 && lc <= 4;
    return outer || inner;
  }
}
