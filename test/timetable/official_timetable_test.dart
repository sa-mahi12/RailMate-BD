/// P43 - official timetable dataset, query, repository and screen tests.
///
/// Everything here is offline: the real bundled JSON is read from disk, and the
/// screens receive an injected repository so no asset bundle or network is
/// touched.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/timetable/official_timetable_screen.dart';
import 'package:railmate_bd/features/timetable/official_train.dart';
import 'package:railmate_bd/features/timetable/timetable_query.dart';
import 'package:railmate_bd/features/timetable/timetable_repository.dart';

String _datasetText() {
  return File('assets/data/official-timetable.json').readAsStringSync();
}

TimetableRepository _repository() {
  return TimetableRepository(loadBundled: () async => _datasetText());
}

void main() {
  late OfficialDataset dataset;

  setUpAll(() {
    dataset = parseOfficialDataset(_datasetText());
  });

  group('dataset', () {
    test('bundled file parses with the expected shape', () {
      expect(dataset.datasetId, 'bd-railway-timetable-54-intercity-2025-03-10');
      expect(dataset.timetableNumber, '54');
      expect(dataset.effectiveFrom, '2025-03-10');
      expect(dataset.trains, hasLength(130));
      expect(dataset.stations, hasLength(29));
      expect(dataset.rowsTranscribed, 130);
      expect(dataset.rowsExcluded, 4);
      expect(dataset.intermediateStopsPublished, isFalse);
      expect(
        dataset.documentHashes.keys,
        containsAll(<String>['eastern', 'western']),
      );
    });

    test('a known published row matches the source exactly', () {
      final OfficialTrain train = dataset.trains.firstWhere(
        (OfficialTrain t) => t.trainNumber == '701',
      );
      expect(train.nameEn, 'Suborno Express');
      expect(train.nameBn, 'সুবর্ণ এক্সপ্রেস');
      expect(train.originStation, 'CTG');
      expect(train.originDeparture, '07:00');
      expect(train.destinationStation, 'DAC');
      expect(train.destinationArrival, '11:55');
      expect(train.offDays, <String>['monday']);
      expect(train.source.document, 'eastern');
      expect(train.source.page, 1);
      expect(train.source.serial, 1);
      expect(train.overnightInferred, isFalse);
      expect(train.durationMinutes, 295);
    });

    test('every row has provenance and no live-status field', () {
      for (final OfficialTrain train in dataset.trains) {
        expect(train.source.document, anyOf('eastern', 'western'));
        expect(train.source.page, greaterThan(0));
        expect(train.source.serial, greaterThan(0));
        expect(train.stopsNote, isNotEmpty);
        expect(train.stops, isEmpty);
      }
      final Map<String, dynamic> raw =
          jsonDecode(_datasetText()) as Map<String, dynamic>;
      final String encoded = jsonEncode(raw['trains']);
      for (final String forbidden in <String>[
        'delay',
        'eta',
        'platform',
        'seat_available',
        'live_fare',
        'occupancy',
      ]) {
        expect(encoded.toLowerCase(), isNot(contains('"$forbidden"')));
      }
    });

    test('overnight flag is true exactly when arrival <= departure', () {
      for (final OfficialTrain train in dataset.trains) {
        expect(
          train.overnightInferred,
          train.arrivalMinutes <= train.departureMinutes,
          reason:
              '${train.trainNumber} ${train.originDeparture}->${train.destinationArrival}',
        );
      }
    });

    test('every station referenced by a train is declared', () {
      final Set<String> ids = dataset.stations
          .map((OfficialStation s) => s.id)
          .toSet();
      for (final OfficialTrain train in dataset.trains) {
        expect(ids, contains(train.originStation));
        expect(ids, contains(train.destinationStation));
      }
    });

    test('stations claim no coordinates', () {
      for (final OfficialStation station in dataset.stations) {
        expect(station.hasVerifiedCoordinates, isFalse);
        expect(station.coordinateProvenance, isNull);
        expect(station.nameProvenance, isNotEmpty);
      }
    });
  });

  group('query', () {
    test('weekday filter removes the published off day only', () {
      final List<OfficialTrain> monday = searchOfficialTimetable(
        dataset,
        const TimetableFilter(weekday: DateTime.monday),
      );
      final List<OfficialTrain> tuesday = searchOfficialTimetable(
        dataset,
        const TimetableFilter(weekday: DateTime.tuesday),
      );
      expect(monday.any((OfficialTrain t) => t.trainNumber == '701'), isFalse);
      expect(tuesday.any((OfficialTrain t) => t.trainNumber == '701'), isTrue);
    });

    test('route filter matches published endpoints only', () {
      final List<OfficialTrain> results = searchOfficialTimetable(
        dataset,
        const TimetableFilter(fromStation: 'CTG', toStation: 'DAC'),
      );
      expect(results, isNotEmpty);
      for (final OfficialTrain train in results) {
        expect(train.originStation, 'CTG');
        expect(train.destinationStation, 'DAC');
      }
      final List<OfficialTrain> reversed = searchOfficialTimetable(
        dataset,
        const TimetableFilter(fromStation: 'DAC', toStation: 'CTG'),
      );
      expect(reversed, isNotEmpty);
      expect(
        reversed
            .map((OfficialTrain t) => t.id)
            .toSet()
            .intersection(results.map((OfficialTrain t) => t.id).toSet()),
        isEmpty,
      );
    });

    test('an unpublished intermediate pair returns nothing', () {
      final List<OfficialTrain> results = searchOfficialTimetable(
        dataset,
        const TimetableFilter(fromStation: 'SYL', toStation: 'CXB'),
      );
      expect(results, isEmpty);
    });

    test('free text matches number, names and station names', () {
      expect(
        searchOfficialTimetable(
          dataset,
          const TimetableFilter(text: 'suborno'),
        ).map((OfficialTrain t) => t.trainNumber),
        containsAll(<String>['701', '702']),
      );
      expect(
        searchOfficialTimetable(
          dataset,
          const TimetableFilter(text: 'কক্সবাজার'),
        ),
        isNotEmpty,
      );
      expect(
        searchOfficialTimetable(
          dataset,
          const TimetableFilter(text: '3131'),
        ).single.nameEn,
        'Mitali Express',
      );
    });

    test('phased services are hidden by default and shown on request', () {
      final List<OfficialTrain> defaultResult = searchOfficialTimetable(
        dataset,
        const TimetableFilter(text: 'tangua'),
      );
      expect(defaultResult, isEmpty);
      final List<OfficialTrain> withPhased = searchOfficialTimetable(
        dataset,
        const TimetableFilter(text: 'tangua', includeNonPublished: true),
      );
      expect(withPhased, hasLength(2));
      expect(withPhased.every((OfficialTrain t) => t.isPhased), isTrue);
    });

    test('results are ordered by departure time', () {
      final List<OfficialTrain> results = searchOfficialTimetable(
        dataset,
        const TimetableFilter(),
      );
      for (int i = 1; i < results.length; i++) {
        expect(
          results[i - 1].departureMinutes <= results[i].departureMinutes,
          isTrue,
        );
      }
    });

    test('station helpers are sorted and consistent', () {
      final List<OfficialStation> options = stationOptions(dataset);
      expect(options, hasLength(dataset.stations.length));
      final List<OfficialTrain> atDhaka = trainsAtStation(dataset, 'DAC');
      expect(atDhaka, isNotEmpty);
      for (final OfficialTrain train in atDhaka) {
        expect(
          train.originStation == 'DAC' || train.destinationStation == 'DAC',
          isTrue,
        );
      }
    });

    test('weekday helpers reject impossible values', () {
      expect(weekdayName(DateTime.monday), 'monday');
      expect(weekdayName(DateTime.sunday), 'sunday');
      expect(() => weekdayName(0), throwsArgumentError);
      expect(() => weekdayName(8), throwsArgumentError);
      expect(weekdayLabel('friday'), 'Friday');
      expect(minutesOfDay('00:00'), 0);
      expect(minutesOfDay('23:59'), 1439);
      expect(() => minutesOfDay('24:00'), throwsFormatException);
      expect(formatMinutes(1445), '00:05');
    });
  });

  group('repository', () {
    test('caches the parsed dataset and shares one in-flight future', () async {
      int loads = 0;
      final TimetableRepository repo = TimetableRepository(
        loadBundled: () async {
          loads++;
          return _datasetText();
        },
      );
      final List<OfficialDataset> both = await Future.wait(
        <Future<OfficialDataset>>[repo.load(), repo.load()],
      );
      expect(loads, 1);
      expect(identical(both[0], both[1]), isTrue);
      await repo.load();
      expect(loads, 1);
      repo.invalidate();
      await repo.load();
      expect(loads, 2);
    });

    test('a corrupt payload throws a FormatException, not a crash', () {
      expect(() => parseOfficialDataset('{not json'), throwsFormatException);
      expect(() => parseOfficialDataset('{}'), throwsFormatException);
      expect(
        () => parseOfficialDataset('{"schema_version":1}'),
        throwsFormatException,
      );
    });

    test('remote refresh failure keeps the bundled dataset', () async {
      final TimetableRepository repo = TimetableRepository(
        loadBundled: () async => _datasetText(),
        fetchRemote: () async => throw const SocketException('offline'),
      );
      final OfficialDataset refreshed = await repo.refresh();
      expect(refreshed.trains, hasLength(130));
      expect(repo.cached, isNotNull);
    });
  });

  group('screen', () {
    Future<void> useTallPhone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('renders the provenance banner and real rows', (
      WidgetTester tester,
    ) async {
      await useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(home: OfficialTimetableScreen(repository: _repository())),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Timetable No. 54 · effective 10 Mar 2025'),
        findsOneWidget,
      );
      expect(find.textContaining('published timetable'), findsWidgets);
      expect(find.text('126 services'), findsOneWidget);
      expect(find.textContaining('Upakul Express'), findsWidgets);
      expect(find.textContaining('Off: Monday'), findsWidgets);
    });

    testWidgets('shows an honest empty state for an impossible route', (
      WidgetTester tester,
    ) async {
      await useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(home: OfficialTimetableScreen(repository: _repository())),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Train or station'),
        'zzz-no-such-train',
      );
      await tester.pumpAndSettle();

      expect(find.text('No published service matches'), findsOneWidget);
      expect(find.textContaining('destination only'), findsOneWidget);
    });

    testWidgets('renders an error state when the asset cannot be read', (
      WidgetTester tester,
    ) async {
      final TimetableRepository broken = TimetableRepository(
        loadBundled: () async => '{broken',
      );
      await tester.pumpWidget(
        MaterialApp(home: OfficialTimetableScreen(repository: broken)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Timetable unavailable'), findsOneWidget);
    });
  });

  group('entry point', () {
    testWidgets('shows the effective date when a dataset is supplied', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfficialTimetableEntryPoint(dataset: dataset, onTap: () {}),
          ),
        ),
      );
      expect(find.text('Official timetable'), findsOneWidget);
      expect(find.textContaining('effective 10 Mar 2025'), findsOneWidget);
    });
  });
}
