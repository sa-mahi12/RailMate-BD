/// P43 - official published timetable screen.
///
/// This is mode A of the product: a read-only, source-backed schedule. It is
/// deliberately separate from the academic demo booking flow - no row from this
/// dataset can become a `Trip`, and no seat, fare, delay, platform or live
/// location is shown.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/design.dart';
import '../../design/state/state.dart';
import 'official_train.dart';
import 'official_train_detail_screen.dart';
import 'timetable_query.dart';
import 'timetable_repository.dart';

/// Opens a URL outside the app; injectable so widget tests stay offline.
typedef ExternalLinkOpener = Future<void> Function(Uri uri);

/// Full official-timetable experience: provenance banner, filters and results.
class OfficialTimetableScreen extends StatefulWidget {
  const OfficialTimetableScreen({
    super.key,
    required this.repository,
    this.openExternal,
  });

  final TimetableRepository repository;
  final ExternalLinkOpener? openExternal;

  @override
  State<OfficialTimetableScreen> createState() =>
      _OfficialTimetableScreenState();
}

class _OfficialTimetableScreenState extends State<OfficialTimetableScreen> {
  late Future<OfficialDataset> _dataset;
  TimetableFilter _filter = const TimetableFilter();

  @override
  void initState() {
    super.initState();
    _dataset = widget.repository.load();
  }

  void _reload() {
    widget.repository.invalidate();
    setState(() {
      _dataset = widget.repository.load();
    });
  }

  Future<void> _openPortal(OfficialDataset dataset) async {
    final Uri uri = Uri.parse(dataset.officialPortal);
    final ExternalLinkOpener opener = widget.openExternal ?? _launchExternal;
    await opener(uri);
  }

  static Future<void> _launchExternal(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Official timetable'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Station directory',
            icon: const Icon(Icons.train_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      OfficialStationDirectoryScreen(
                        repository: widget.repository,
                      ),
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<OfficialDataset>(
        future: _dataset,
        builder:
            (BuildContext context, AsyncSnapshot<OfficialDataset> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _TimetableLoading();
              }
              final Object? error = snapshot.error;
              if (error != null) {
                return ErrorState(
                  title: 'Timetable unavailable',
                  message:
                      'The bundled official timetable could not be read. This build '
                      'cannot show a schedule until it is reinstalled.',
                  onRetry: _reload,
                );
              }
              final OfficialDataset dataset = snapshot.data!;
              return _buildBody(context, dataset);
            },
      ),
    );
  }

  Widget _buildBody(BuildContext context, OfficialDataset dataset) {
    final List<OfficialTrain> results = searchOfficialTimetable(
      dataset,
      _filter,
    );
    final List<OfficialStation> stations = stationOptions(dataset);

    return RefreshIndicator(
      onRefresh: () async {
        _reload();
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: <Widget>[
          _ProvenanceBanner(
            dataset: dataset,
            onOpenPortal: () => _openPortal(dataset),
          ),
          const SizedBox(height: AppSpacing.s16),
          _FilterCard(
            stations: stations,
            filter: _filter,
            onChanged: (TimetableFilter next) {
              setState(() => _filter = next);
            },
          ),
          const SizedBox(height: AppSpacing.s16),
          _ResultHeader(count: results.length, filter: _filter),
          const SizedBox(height: AppSpacing.s8),
          if (results.isEmpty)
            EmptyState(
              icon: Icons.search_off,
              title: 'No published service matches',
              message: _filter.hasRouteOrDayFilter
                  ? 'The published summary lists each service by its origin and '
                        'destination only, so intermediate-station pairs return '
                        'nothing. Try the exact endpoints or clear the filters.'
                  : 'Clear the search box to list every imported service.',
            )
          else
            ...results.map(
              (OfficialTrain train) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                child: _TrainCard(
                  train: train,
                  dataset: dataset,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            OfficialTrainDetailScreen(
                              train: train,
                              dataset: dataset,
                              openExternal: widget.openExternal,
                            ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }
}

/// Home-screen entry card; the host decides where it navigates.
class OfficialTimetableEntryPoint extends StatelessWidget {
  const OfficialTimetableEntryPoint({
    super.key,
    required this.onTap,
    this.dataset,
  });

  final VoidCallback onTap;
  final OfficialDataset? dataset;

  @override
  Widget build(BuildContext context) {
    final OfficialDataset? data = dataset;
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.cardRadius,
      elevation: 0,
      child: InkWell(
        borderRadius: AppRadii.cardRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: AppRadii.chipRadius,
                ),
                child: const Icon(Icons.schedule, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Official timetable', style: AppTypography.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      data == null
                          ? 'Published Bangladesh Railway schedule - not live status'
                          : 'Timetable No. ${data.timetableNumber} · effective '
                                '${formatIsoDate(data.effectiveFrom)} · published schedule only',
                      style: AppTypography.metadata,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvenanceBanner extends StatelessWidget {
  const _ProvenanceBanner({required this.dataset, required this.onOpenPortal});

  final OfficialDataset dataset;
  final VoidCallback onOpenPortal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.verified_outlined,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  'Timetable No. ${dataset.timetableNumber} · effective '
                  '${formatIsoDate(dataset.effectiveFrom)}',
                  style: AppTypography.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(dataset.notice, style: AppTypography.body),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Last checked ${formatIsoDate(dataset.lastVerified)} · '
            '${dataset.rowsTranscribed} services imported · '
            '${dataset.rowsExcluded} printed rows excluded as ambiguous',
            style: AppTypography.caption,
          ),
          if (dataset.coverageGaps.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Coverage limit: ${dataset.coverageGaps.join('; ')}',
              style: AppTypography.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenPortal,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Official e-ticket portal'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.stations,
    required this.filter,
    required this.onChanged,
  });

  final List<OfficialStation> stations;
  final TimetableFilter filter;
  final ValueChanged<TimetableFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _StationDropdown(
                  label: 'From',
                  value: filter.fromStation,
                  stations: stations,
                  onChanged: (String? value) {
                    onChanged(
                      value == null
                          ? filter.copyWith(clearFrom: true)
                          : filter.copyWith(fromStation: value),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: _StationDropdown(
                  label: 'To',
                  value: filter.toStation,
                  stations: stations,
                  onChanged: (String? value) {
                    onChanged(
                      value == null
                          ? filter.copyWith(clearTo: true)
                          : filter.copyWith(toStation: value),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: filter.weekday,
                  decoration: const InputDecoration(
                    labelText: 'Travels on',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<int>>[
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Any day'),
                    ),
                    for (
                      int day = DateTime.monday;
                      day <= DateTime.sunday;
                      day++
                    )
                      DropdownMenuItem<int>(
                        value: day,
                        child: Text(weekdayLabel(weekdayName(day))),
                      ),
                  ],
                  onChanged: (int? value) {
                    onChanged(
                      value == null
                          ? filter.copyWith(clearWeekday: true)
                          : filter.copyWith(weekday: value),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: TextFormField(
                  initialValue: filter.text,
                  decoration: const InputDecoration(
                    labelText: 'Train or station',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (String value) {
                    onChanged(filter.copyWith(text: value));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Filters match the published origin and destination only; the source '
            'summary does not list intermediate stops.',
            style: AppTypography.caption,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Show phased services', style: AppTypography.body),
                      Text(
                        'Published as planned, not yet operational',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: filter.includeNonPublished,
                  onChanged: (bool value) {
                    onChanged(filter.copyWith(includeNonPublished: value));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationDropdown extends StatelessWidget {
  const _StationDropdown({
    required this.label,
    required this.value,
    required this.stations,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<OfficialStation> stations;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem<String>(value: null, child: Text('Any')),
        for (final OfficialStation station in stations)
          DropdownMenuItem<String>(
            value: station.id,
            child: Text(
              '${station.nameEn} (${station.id})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.count, required this.filter});

  final int count;
  final TimetableFilter filter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          count == 1 ? '1 service' : '$count services',
          style: AppTypography.sectionTitle,
        ),
        const Spacer(),
        Text(
          filter.includeNonPublished ? 'including phased' : 'published only',
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _TrainCard extends StatelessWidget {
  const _TrainCard({
    required this.train,
    required this.dataset,
    required this.onTap,
  });

  final OfficialTrain train;
  final OfficialDataset dataset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.cardRadius,
      child: InkWell(
        borderRadius: AppRadii.cardRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    train.trainNumber,
                    style: AppTypography.cardTitle.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      train.displayName,
                      style: AppTypography.cardTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (train.isPhased)
                    _Chip(label: 'Phased', color: AppColors.mutedText),
                ],
              ),
              if (train.nameBn != null && train.nameEn != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(train.nameBn!, style: AppTypography.caption),
                ),
              const SizedBox(height: AppSpacing.s8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Endpoint(
                      time: train.originDeparture,
                      station: dataset.stationName(train.originStation),
                      alignment: CrossAxisAlignment.start,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.secondaryText,
                  ),
                  Expanded(
                    child: _Endpoint(
                      time: train.destinationArrival,
                      station: dataset.stationName(train.destinationStation),
                      alignment: CrossAxisAlignment.end,
                      nextDay: train.overnightInferred,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s4,
                children: <Widget>[
                  _Chip(
                    label: train.offDays.isEmpty
                        ? 'No weekly off day published'
                        : 'Off: ${train.offDays.map(weekdayLabel).join(', ')}',
                    color: train.offDays.isEmpty
                        ? AppColors.success
                        : AppColors.secondaryText,
                  ),
                  _Chip(
                    label: _zoneLabel(train.zone),
                    color: AppColors.secondaryText,
                  ),
                  if (train.isInternational)
                    const _Chip(
                      label: 'International',
                      color: AppColors.primary,
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

class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.time,
    required this.station,
    required this.alignment,
    this.nextDay = false,
  });

  final String time;
  final String station;
  final CrossAxisAlignment alignment;
  final bool nextDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        Text(
          time,
          style: AppTypography.cardTitle.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        Text(station, style: AppTypography.metadata),
        if (nextDay) Text('next day (inferred)', style: AppTypography.caption),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadii.chipRadius,
      ),
      child: Text(label, style: AppTypography.caption.copyWith(color: color)),
    );
  }
}

class _TimetableLoading extends StatelessWidget {
  const _TimetableLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: const <Widget>[
        SkeletonCard(height: 150),
        SizedBox(height: AppSpacing.s16),
        SkeletonCard(height: 210),
        SizedBox(height: AppSpacing.s16),
        SkeletonCard(height: 120),
        SizedBox(height: AppSpacing.s12),
        SkeletonCard(height: 120),
      ],
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

/// `2025-03-10` -> `10 Mar 2025`; returns the input unchanged when it is not an
/// ISO date so a malformed dataset cannot crash the banner.
String formatIsoDate(String iso) {
  final List<String> parts = iso.split('-');
  if (parts.length != 3) {
    return iso;
  }
  final int? year = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return iso;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return iso;
  }
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '$day ${months[month - 1]} $year';
}
