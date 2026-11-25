/// P43 - pure search logic over the official timetable dataset.
///
/// Deliberate limits, because the source summary tables publish only the
/// origin and destination of each service:
/// * a route search matches the published endpoints exactly; it never claims
///   that a train stops at an intermediate station;
/// * a weekday filter removes services whose published weekly off day is that
///   weekday;
/// * phased services are hidden unless the caller asks for them.
library;

import 'official_train.dart';

/// Search criteria for [searchOfficialTimetable].
class TimetableFilter {
  /// Published origin station id, or null for any.
  final String? fromStation;

  /// Published destination station id, or null for any.
  final String? toStation;

  /// `DateTime.monday`..`DateTime.sunday`, or null to ignore the weekday.
  final int? weekday;

  /// Free text over train number, names and station names.
  final String text;

  /// Zone keys to keep; empty means every zone.
  final Set<String> zones;

  /// Service classes to keep; empty means every class.
  final Set<String> serviceClasses;

  /// When true, phased (published but not yet operational) services appear.
  final bool includeNonPublished;

  const TimetableFilter({
    this.fromStation,
    this.toStation,
    this.weekday,
    this.text = '',
    this.zones = const <String>{},
    this.serviceClasses = const <String>{},
    this.includeNonPublished = false,
  });

  TimetableFilter copyWith({
    String? fromStation,
    String? toStation,
    int? weekday,
    String? text,
    Set<String>? zones,
    Set<String>? serviceClasses,
    bool? includeNonPublished,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearWeekday = false,
  }) {
    return TimetableFilter(
      fromStation: clearFrom ? null : (fromStation ?? this.fromStation),
      toStation: clearTo ? null : (toStation ?? this.toStation),
      weekday: clearWeekday ? null : (weekday ?? this.weekday),
      text: text ?? this.text,
      zones: zones ?? this.zones,
      serviceClasses: serviceClasses ?? this.serviceClasses,
      includeNonPublished: includeNonPublished ?? this.includeNonPublished,
    );
  }

  /// True when any filter other than the free-text box is active.
  bool get hasRouteOrDayFilter =>
      fromStation != null || toStation != null || weekday != null;
}

/// Applies [filter] to [dataset] and returns the matching services sorted by
/// departure time, then train number.
List<OfficialTrain> searchOfficialTimetable(
  OfficialDataset dataset,
  TimetableFilter filter,
) {
  final String needle = filter.text.trim().toLowerCase();
  final List<OfficialTrain> matches = dataset.trains.where((
    OfficialTrain train,
  ) {
    if (!filter.includeNonPublished && !train.isPublished) {
      return false;
    }
    if (filter.zones.isNotEmpty && !filter.zones.contains(train.zone)) {
      return false;
    }
    if (filter.serviceClasses.isNotEmpty &&
        !filter.serviceClasses.contains(train.serviceClass)) {
      return false;
    }
    if (filter.fromStation != null &&
        train.originStation != filter.fromStation) {
      return false;
    }
    if (filter.toStation != null &&
        train.destinationStation != filter.toStation) {
      return false;
    }
    final int? weekday = filter.weekday;
    if (weekday != null && train.isOffOnWeekday(weekday)) {
      return false;
    }
    if (needle.isEmpty) {
      return true;
    }
    return _haystack(dataset, train).contains(needle);
  }).toList();

  matches.sort((OfficialTrain a, OfficialTrain b) {
    final int byTime = a.departureMinutes.compareTo(b.departureMinutes);
    if (byTime != 0) {
      return byTime;
    }
    return a.trainNumber.compareTo(b.trainNumber);
  });
  return List<OfficialTrain>.unmodifiable(matches);
}

/// Every published service that starts or ends at [stationId].
List<OfficialTrain> trainsAtStation(
  OfficialDataset dataset,
  String stationId, {
  bool includeNonPublished = false,
}) {
  return List<OfficialTrain>.unmodifiable(
    dataset.trains.where((OfficialTrain train) {
      if (!includeNonPublished && !train.isPublished) {
        return false;
      }
      return train.originStation == stationId ||
          train.destinationStation == stationId;
    }).toList()..sort((OfficialTrain a, OfficialTrain b) {
      return a.departureMinutes.compareTo(b.departureMinutes);
    }),
  );
}

/// Station choices for a picker, sorted by English name.
List<OfficialStation> stationOptions(OfficialDataset dataset) {
  final List<OfficialStation> stations = List<OfficialStation>.of(
    dataset.stations,
  );
  stations.sort((OfficialStation a, OfficialStation b) {
    return a.nameEn.toLowerCase().compareTo(b.nameEn.toLowerCase());
  });
  return List<OfficialStation>.unmodifiable(stations);
}

/// Honest label for how many rows the dataset covers, used by the UI banner.
String coverageSummary(OfficialDataset dataset) {
  return '${dataset.rowsTranscribed} published intercity services imported '
      'from Timetable No. ${dataset.timetableNumber}';
}

String _haystack(OfficialDataset dataset, OfficialTrain train) {
  final StringBuffer buffer = StringBuffer()
    ..write(train.trainNumber.toLowerCase())
    ..write(' ')
    ..write((train.nameEn ?? '').toLowerCase())
    ..write(' ')
    ..write((train.nameBn ?? '').toLowerCase())
    ..write(' ')
    ..write(dataset.stationName(train.originStation).toLowerCase())
    ..write(' ')
    ..write(dataset.stationName(train.destinationStation).toLowerCase());
  return buffer.toString();
}
