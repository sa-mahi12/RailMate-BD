/// P43 - official train detail and the derived station directory.
///
/// Both screens show only what the published timetable contains. The detail
/// screen prints the exact provenance (document, page, serial) and says plainly
/// that intermediate stops are not published in this source. The directory
/// never claims coordinates: the timetable does not carry them.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/design.dart';
import '../../design/state/state.dart';
import 'official_train.dart';
import 'official_timetable_screen.dart' show ExternalLinkOpener, formatIsoDate;
import 'timetable_query.dart';
import 'timetable_repository.dart';

/// Everything the source publishes about one train direction.
class OfficialTrainDetailScreen extends StatelessWidget {
  const OfficialTrainDetailScreen({
    super.key,
    required this.train,
    required this.dataset,
    this.openExternal,
  });

  final OfficialTrain train;
  final OfficialDataset dataset;
  final ExternalLinkOpener? openExternal;

  Future<void> _openPortal() async {
    final Uri uri = Uri.parse(dataset.officialPortal);
    final ExternalLinkOpener opener =
        openExternal ??
        (Uri target) => launchUrl(target, mode: LaunchMode.externalApplication);
    await opener(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('${train.trainNumber} ${train.displayName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: <Widget>[
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(train.displayName, style: AppTypography.pageHeadline),
                if (train.nameBn != null)
                  Text(train.nameBn!, style: AppTypography.body),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TimeBlock(
                        label: 'Departs',
                        time: train.originDeparture,
                        station: dataset.stationName(train.originStation),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: AppColors.secondaryText,
                    ),
                    Expanded(
                      child: _TimeBlock(
                        label: 'Arrives',
                        time: train.destinationArrival,
                        station: dataset.stationName(train.destinationStation),
                        nextDay: train.overnightInferred,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  children: <Widget>[
                    _FactChip(
                      label: train.offDays.isEmpty
                          ? 'No weekly off day published'
                          : 'Weekly off: ${train.offDays.map(weekdayLabel).join(', ')}',
                    ),
                    _FactChip(label: _zoneLabel(train.zone)),
                    _FactChip(label: _classLabel(train.serviceClass)),
                    if (train.isPhased)
                      const _FactChip(label: 'Phased - not yet operational'),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                Text(
                  'Published journey time: ${_durationLabel(train.durationMinutes)}'
                  '${train.overnightInferred ? ' (arrival time is on the next day; inferred from the two published times)' : ''}',
                  style: AppTypography.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Route and stops', style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.s8),
                Text(train.stopsNote, style: AppTypography.body),
                if (train.stops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s8),
                    child: Text(
                      'Nothing is inferred: this build does not guess intermediate '
                      'stations, arrival times or platforms.',
                      style: AppTypography.caption,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Source', style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.s8),
                _SourceRow(
                  label: 'Document',
                  value: train.source.document == 'eastern'
                      ? 'Eastern Zone timetable (PDF)'
                      : 'Western Zone timetable (PDF)',
                ),
                _SourceRow(
                  label: 'Page / row',
                  value: '${train.source.page} / ${train.source.serial}',
                ),
                _SourceRow(
                  label: 'Timetable',
                  value: 'No. ${dataset.timetableNumber}',
                ),
                _SourceRow(
                  label: 'Effective',
                  value: formatIsoDate(dataset.effectiveFrom),
                ),
                _SourceRow(
                  label: 'Retrieved',
                  value: formatIsoDate(dataset.retrieved),
                ),
                _SourceRow(
                  label: 'Last verified',
                  value: formatIsoDate(dataset.lastVerified),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  'Times are the published schedule. They are not live running '
                  'status: no location, delay, ETA, platform or seat inventory is '
                  'shown, and no fare is guessed.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          FilledButton.icon(
            onPressed: _openPortal,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Check current fare and availability'),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Opens the official Bangladesh Railway e-ticket portal in your '
            'browser. RailMate does not collect portal credentials or sell tickets.',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }
}

/// Stations derived from the published timetable, with the services touching
/// each one. No coordinates and no facilities are claimed.
class OfficialStationDirectoryScreen extends StatefulWidget {
  const OfficialStationDirectoryScreen({super.key, required this.repository});

  final TimetableRepository repository;

  @override
  State<OfficialStationDirectoryScreen> createState() =>
      _OfficialStationDirectoryScreenState();
}

class _OfficialStationDirectoryScreenState
    extends State<OfficialStationDirectoryScreen> {
  late Future<OfficialDataset> _dataset;

  @override
  void initState() {
    super.initState();
    _dataset = widget.repository.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Stations in the timetable'),
      ),
      body: FutureBuilder<OfficialDataset>(
        future: _dataset,
        builder: (BuildContext context, AsyncSnapshot<OfficialDataset> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              title: 'Station directory unavailable',
              message: 'The bundled timetable could not be read.',
              onRetry: () {
                widget.repository.invalidate();
                setState(() => _dataset = widget.repository.load());
              },
            );
          }
          final OfficialDataset dataset = snapshot.data!;
          final List<OfficialStation> stations = stationOptions(dataset);
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.s16),
            itemCount: stations.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s12),
            itemBuilder: (BuildContext context, int index) {
              final OfficialStation station = stations[index];
              final List<OfficialTrain> services = trainsAtStation(
                dataset,
                station.id,
              );
              return _DetailCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(station.nameEn, style: AppTypography.cardTitle),
                    Text(
                      '${station.nameBn} · ${station.id}',
                      style: AppTypography.metadata,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      '${services.length} published '
                      '${services.length == 1 ? 'service' : 'services'} start or end here',
                      style: AppTypography.body,
                    ),
                    if (!station.hasVerifiedCoordinates)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Coordinates not verified - the published timetable does '
                          'not carry them.',
                          style: AppTypography.caption,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s4,
                      children: services
                          .map(
                            (OfficialTrain train) => _FactChip(
                              label:
                                  '${train.trainNumber} ${train.displayName}',
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.time,
    required this.station,
    this.nextDay = false,
    this.alignEnd = false,
  });

  final String label;
  final String time;
  final String station;
  final bool nextDay;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTypography.caption),
        Text(time, style: AppTypography.pageHeadline),
        Text(station, style: AppTypography.body),
        if (nextDay) Text('next day (inferred)', style: AppTypography.caption),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: AppTypography.metadata),
          ),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: AppRadii.chipRadius,
      ),
      child: Text(label, style: AppTypography.caption),
    );
  }
}

String _zoneLabel(String zone) {
  switch (zone) {
    case 'eastern':
      return 'Eastern Zone';
    case 'western':
      return 'Western Zone';
    default:
      return zone;
  }
}

String _classLabel(String serviceClass) {
  switch (serviceClass) {
    case 'intercity':
      return 'Intercity';
    case 'intercity_phased':
      return 'Intercity (phased)';
    case 'international':
      return 'International';
    default:
      return serviceClass;
  }
}

String _durationLabel(int minutes) {
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  if (hours == 0) {
    return '$rest min';
  }
  if (rest == 0) {
    return '${hours}h';
  }
  return '${hours}h ${rest}m';
}
