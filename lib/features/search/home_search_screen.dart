import 'package:flutter/material.dart';

import 'models/station.dart';
import 'search_date_utils.dart';
import 'search_state.dart';

const Color _primaryTeal = Color(0xFF0E5A66);
const Color _pageBackground = Color(0xFFF4F7F9);

/// Ref-1 home/search screen: greeting header, From/To cards with a swap
/// button, journey date with a 5-day chip strip, Search Trains button and
/// a Station Guide promo card.
///
/// Wiring: pass the shared [SearchState]; [onSearchSubmitted] fires after a
/// successful search so the host can push the results screen. Station Guide
/// uses [onStationGuideTap] when provided, otherwise it tries the
/// `station-guide` named route (registered later in I01) and falls back to
/// a "coming in I01" snackbar when the route is missing.
class HomeSearchScreen extends StatelessWidget {
  final SearchState state;
  final VoidCallback? onSearchSubmitted;
  final VoidCallback? onStationGuideTap;

  const HomeSearchScreen({
    super.key,
    required this.state,
    this.onSearchSubmitted,
    this.onStationGuideTap,
  });

  void _openStationGuide(BuildContext context) {
    if (onStationGuideTap != null) {
      onStationGuideTap!();
      return;
    }
    try {
      Navigator.pushNamed(context, 'station-guide');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station Guide is coming in I01.')),
      );
    }
  }

  Future<void> _submit(BuildContext context) async {
    await state.search();
    if (!context.mounted) return;
    if (state.status == SearchStatus.loaded) {
      onSearchSubmitted?.call();
    } else if (state.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: state.selectedDate,
      firstDate: dayStartOf(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) state.selectDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRouteCard(context),
                      const SizedBox(height: 12),
                      _buildDateCard(context),
                      const SizedBox(height: 12),
                      _buildSearchButton(context),
                      const SizedBox(height: 12),
                      _buildStationGuideCard(context),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 72),
      decoration: const BoxDecoration(
        color: _primaryTeal,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good morning,',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          SizedBox(height: 4),
          Text(
            "Let's plan\nyour journey",
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              children: [
                _StationField(
                  label: 'From',
                  icon: Icons.trip_origin,
                  value: state.origin,
                  stations: state.stations,
                  hint: 'Select origin',
                  onChanged: state.selectOrigin,
                ),
                const Divider(height: 24),
                _StationField(
                  label: 'To',
                  icon: Icons.location_on_outlined,
                  value: state.destination,
                  stations: state.stations,
                  hint: 'Select destination',
                  onChanged: state.selectDestination,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: state.swapEndpoints,
            icon: const Icon(Icons.swap_vert),
            tooltip: 'Swap origin and destination',
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(BuildContext context) {
    final chips = dateStrip(state.selectedDate);
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
          InkWell(
            onTap: () => _pickDate(context),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, color: _primaryTeal),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Journey date',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      formatJourneyDate(state.selectedDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final day in chips)
                _DateChip(
                  date: day,
                  selected: dayStartOf(day) == dayStartOf(state.selectedDate),
                  onTap: () => state.selectDate(day),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchButton(BuildContext context) {
    final loading = state.isLoading;
    return FilledButton.icon(
      onPressed: loading ? null : () => _submit(context),
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.search),
      label: Text(loading ? 'Searching…' : 'Search Trains'),
      style: FilledButton.styleFrom(
        backgroundColor: _primaryTeal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildStationGuideCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openStationGuide(context),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.maps_home_work_outlined,
                color: Color(0xFF1E9E6A),
                size: 32,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Station Guide',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Explore railway stations with maps, photos and helpful info.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationField extends StatelessWidget {
  final String label;
  final IconData icon;
  final Station? value;
  final List<Station> stations;
  final String hint;
  final ValueChanged<Station?> onChanged;

  const _StationField({
    required this.label,
    required this.icon,
    required this.value,
    required this.stations,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _primaryTeal),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<Station>(
            key: ValueKey('station_${label}_${value?.id}'),
            initialValue: value,
            hint: Text(hint),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: [
              for (final station in stations)
                DropdownMenuItem<Station>(
                  value: station,
                  child: Text(
                    '${station.name} (${station.code})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  const _DateChip({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primaryTeal : _pageBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _primaryTeal : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Text(
              date.day.toString().padLeft(2, '0'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              weekdays[date.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
