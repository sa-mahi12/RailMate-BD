import 'package:flutter/material.dart';

import '../../search/models/trip.dart';
import '../../search/models/trip_seat.dart';
import '../../search/search_date_utils.dart';
import 'seat_selection_state.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);
const Color _seatAvailableBg = Color(0xFFEAF0F6);
const Color _seatBookedBg = Color(0xFFF2994A);
const Color _seatReservedBg = Color(0xFFB0BEC5);
const Color _accentGreen = Color(0xFF1E9E6A);

/// Ref-1 "Select Your Seat" screen: train header card, route row, legend,
/// coach chips, seat grid, selected-seats bar and continue button.
///
/// Renders purely from [state.seats] ([TripSeat] rows where
/// `!isAvailable` means unavailable/disabled — really booked
/// (`bookingId != null`) or demo-held (`demoReserved == true`)). Demo-held
/// seats render disabled in a distinct grey "Reserved" shade; really-booked
/// seats keep the orange "Booked" shade. Performs no client writes of
/// booked state — booking is the A05 lane. [onContinue] receives the sorted
/// selected codes when the user taps "Continue to Passenger Details".
///
/// The seat grid is derived from the data (grouped by row prefix, five
/// columns) so no hardcoded seat map is embedded: with the demo seed this
/// yields rows A-E x 1-5 as in the reference.
class SeatSelectionScreen extends StatefulWidget {
  final Trip trip;
  final SeatSelectionState state;
  final ValueChanged<List<String>> onContinue;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final String classLabel;
  final String coachLabel;

  const SeatSelectionScreen({
    super.key,
    required this.trip,
    required this.state,
    required this.onContinue,
    this.originCode = '--',
    this.originName = '--',
    this.destinationCode = '--',
    this.destinationName = '--',
    this.classLabel = '5 Chair',
    this.coachLabel = 'Coach A',
  });

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.state.status == SeatSelectionStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.state.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryTeal,
        foregroundColor: Colors.white,
        title: const Text('Select Your Seat'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh seats',
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.state.refresh(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.state;
    if (state.status == SeatSelectionStatus.loading && state.seats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == SeatSelectionStatus.error && state.seats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage ?? 'Could not load seats. Please try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => state.load(),
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryTeal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 16),
              const Icon(
                Icons.event_seat_outlined,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              const Text(
                'No seats available for this trip',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try another train or date.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderCard(),
        if (state.isStale)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8B93E)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Seat map may be stale. Refresh for the latest availability.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => state.refresh(),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _buildLegend(),
        const SizedBox(height: 12),
        _buildCoachChips(),
        const SizedBox(height: 12),
        _buildSeatGrid(),
        const SizedBox(height: 12),
        _buildSelectedBar(),
        const SizedBox(height: 12),
        _buildContinueButton(),
      ],
    );
  }

  Widget _buildHeaderCard() {
    final trip = widget.trip;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  trip.trainName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${widget.classLabel} | ${widget.coachLabel}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.originCode,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.originName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.destinationCode,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.destinationName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTime12(trip.departureAt),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    formatShortDate(trip.departureAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              Column(
                children: [
                  const Icon(Icons.train, color: _primaryTeal, size: 20),
                  Text(
                    formatDuration(trip.departureAt, trip.arrivalAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatTime12(trip.arrivalAt),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    formatShortDate(trip.arrivalAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: const [
        _LegendItem(color: _seatAvailableBg, label: 'Available'),
        _LegendItem(color: _primaryTeal, label: 'Selected'),
        _LegendItem(color: _seatBookedBg, label: 'Booked'),
        _LegendItem(color: _seatReservedBg, label: 'Reserved'),
      ],
    );
  }

  Widget _buildCoachChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _primaryTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${widget.classLabel} (A)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Single coach in v1 — multi-coach selection comes later.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  /// Groups [TripSeat] rows by leading-letter prefix and numeric suffix so
  /// the grid follows the data (demo seed yields A-E x 1-5, five columns).
  Widget _buildSeatGrid() {
    final seats = List<TripSeat>.of(widget.state.seats)
      ..sort((a, b) => a.seatCode.compareTo(b.seatCode));
    final rows = _groupByRow(seats);
    if (rows.isEmpty) {
      // Fallback: flat 5-column grid when codes do not follow Row+Number.
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.4,
        ),
        itemCount: seats.length,
        itemBuilder: (context, index) => _SeatCell(
          seat: seats[index],
          selected: widget.state.isSelected(seats[index].seatCode),
          onTap: () => widget.state.toggle(seats[index].seatCode),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in rows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final seat in entry.value)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _SeatCell(
                        seat: seat,
                        selected: widget.state.isSelected(seat.seatCode),
                        onTap: () => widget.state.toggle(seat.seatCode),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Groups seats by leading letters (e.g. 'C' of 'C4'); returns an empty
  /// map when any code does not match the pattern so the caller falls back
  /// to a flat grid.
  Map<String, List<TripSeat>> _groupByRow(List<TripSeat> seats) {
    final pattern = RegExp(r'^([A-Za-z]+)(\d+)$');
    final groups = <String, List<TripSeat>>{};
    for (final seat in seats) {
      final match = pattern.firstMatch(seat.seatCode);
      if (match == null) return <String, List<TripSeat>>{};
      groups.putIfAbsent(match.group(1)!.toUpperCase(), () => []).add(seat);
    }
    final orderedKeys = groups.keys.toList()..sort();
    final ordered = <String, List<TripSeat>>{};
    for (final key in orderedKeys) {
      final list = groups[key]!;
      list.sort((a, b) {
        int numOf(TripSeat s) =>
            int.parse(RegExp(r'\d+').firstMatch(s.seatCode)!.group(0)!);
        return numOf(a).compareTo(numOf(b));
      });
      ordered[key] = list;
    }
    return ordered;
  }

  Widget _buildSelectedBar() {
    final codes = widget.state.selectedSeatCodes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Selected Seats (${codes.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            codes.isEmpty ? '--' : codes.join(', '),
            style: const TextStyle(
              color: _accentGreen,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    final codes = widget.state.selectedSeatCodes;
    final enabled =
        codes.isNotEmpty && codes.length <= SeatSelectionState.maxSelection;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? () => widget.onContinue(codes) : null,
        style: FilledButton.styleFrom(
          backgroundColor: _primaryTeal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Continue to Passenger Details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _SeatCell extends StatelessWidget {
  final TripSeat seat;
  final bool selected;
  final VoidCallback onTap;

  const _SeatCell({
    required this.seat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Unavailable covers both really-booked and demo-held seats
    // (TripSeat.isAvailable == false); both are disabled. Demo-held seats
    // get a distinct grey shade via TripSeat.isDemoHeld — no structural
    // change to the cell API, which already receives the full TripSeat.
    final unavailable = !seat.isAvailable;
    final reserved = seat.isDemoHeld;
    final Color background;
    final Color foreground;
    if (reserved) {
      background = _seatReservedBg;
      foreground = Colors.white;
    } else if (unavailable) {
      background = _seatBookedBg;
      foreground = Colors.white;
    } else if (selected) {
      background = _primaryTeal;
      foreground = Colors.white;
    } else {
      background = _seatAvailableBg;
      foreground = Colors.black87;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: unavailable ? null : onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          seat.seatCode,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
