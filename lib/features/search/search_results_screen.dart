import 'package:flutter/material.dart';

import 'models/trip.dart';
import 'search_date_utils.dart';
import 'search_state.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Ref-1 search-results screen: route header card (station codes plus
/// date/passengers/class), a horizontal date strip, and train cards
/// (name, BDT fare, times, duration, coach info).
///
/// Tapping a train card calls [onSelectTrip] so the host can push seat
/// selection. [onRetry] defaults to re-running the last search;
/// [onDateSelected] defaults to selecting the date and re-searching.
/// Empty results render "No trains on this route/date"; network and
/// timeout failures render an error state with a retry button — a timeout
/// is never shown as "no trains".
class SearchResultsScreen extends StatelessWidget {
  final SearchState state;
  final ValueChanged<Trip> onSelectTrip;
  final VoidCallback? onRetry;
  final ValueChanged<DateTime>? onDateSelected;

  const SearchResultsScreen({
    super.key,
    required this.state,
    required this.onSelectTrip,
    this.onRetry,
    this.onDateSelected,
  });

  Future<void> _changeDate(DateTime date) async {
    if (onDateSelected != null) {
      onDateSelected!(date);
    } else {
      state.selectDate(date);
      await state.search();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryTeal,
        foregroundColor: Colors.white,
        title: const Text('Search Results'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return Column(
            children: [
              _buildRouteHeader(),
              _buildDateStrip(),
              Expanded(child: _buildBody(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRouteHeader() {
    final originId =
        state.origin?.id ?? state.results.firstOrNull?.originStationId ?? '';
    final destinationId =
        state.destination?.id ??
        state.results.firstOrNull?.destinationStationId ??
        '';
    return Container(
      margin: const EdgeInsets.all(16),
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
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.stationCode(originId),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      state.stationName(originId),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.train, color: _primaryTeal),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      state.stationCode(destinationId),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      state.stationName(destinationId),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text(
                    formatJourneyDate(state.selectedDate),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Passengers',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text('1 Adult', style: TextStyle(fontSize: 12)),
                ],
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Class',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text('All Classes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateStrip() {
    final days = dateStrip(state.selectedDate);
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = days[index];
          final selected = dayStartOf(day) == dayStartOf(state.selectedDate);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _changeDate(day),
            child: Container(
              width: 56,
              decoration: BoxDecoration(
                color: selected ? _primaryTeal : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? _primaryTeal : Colors.grey.shade300,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    formatJourneyDate(day).split(',').first,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (state.isLoading && state.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == SearchStatus.error) {
      final isTimeout = state.errorKind == SearchErrorKind.timeout;
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
                isTimeout
                    ? 'The request timed out. Please check your connection and try again.'
                    : 'Something went wrong while searching. Please try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry ?? state.retry,
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
    if (state.isEmpty ||
        (state.status == SearchStatus.loaded && state.results.isEmpty)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.train_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No trains on this route/date',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 4),
              Text(
                'Try another date or route.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    final String? rankingNote = state.rankingNote;
    return Column(
      children: [
        // F17 honesty caption: shown only when on-device smart ranking
        // could not run (the list below is the unranked fetch order).
        if (rankingNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              rankingNote,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.results.length,
            itemBuilder: (context, index) {
              final trip = state.results[index];
              return _TripCard(
                trip: trip,
                originCode: state.stationCode(trip.originStationId),
                originName: state.stationName(trip.originStationId),
                destinationCode: state.stationCode(trip.destinationStationId),
                destinationName: state.stationName(trip.destinationStationId),
                onTap: () => onSelectTrip(trip),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final VoidCallback onTap;

  const _TripCard({
    required this.trip,
    required this.originCode,
    required this.originName,
    required this.destinationCode,
    required this.destinationName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    'BDT ${trip.fareBdt}',
                    style: const TextStyle(
                      color: _primaryTeal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          originCode,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          originName,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Chair',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          destinationCode,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          destinationName,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Icon(Icons.train, color: _primaryTeal, size: 20),
                      Text(
                        formatDuration(trip.departureAt, trip.arrivalAt),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
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
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
