import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/design.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';
import 'package:railmate_bd/features/search/search_results_screen.dart';
import 'package:railmate_bd/features/search/search_state.dart';

/// V4 P13 widget pins: results loading skeleton, timeout-vs-generic error
/// copy with retry, empty copy, and trip-card tap selection.
void main() {
  const origin = Station(id: 'o', code: 'DAC', name: 'Dhaka');
  const destination = Station(id: 'd', code: 'CGP', name: 'Chattogram');

  Trip trip(String id, String name) => Trip(
    id: id,
    trainName: name,
    originStationId: 'o',
    destinationStationId: 'd',
    departureAt: DateTime(2026, 10, 6, 7, 0),
    arrivalAt: DateTime(2026, 10, 6, 12, 30),
    fareBdt: 625,
    active: true,
  );

  SearchState stateWith({
    SearchStatus status = SearchStatus.loaded,
    SearchErrorKind errorKind = SearchErrorKind.none,
    List<Trip> results = const <Trip>[],
  }) {
    final state = SearchState(api: _NeverApi());
    state
      ..stations = const [origin, destination]
      ..origin = origin
      ..destination = destination
      ..results = results
      ..status = status
      ..errorKind = errorKind;
    return state;
  }

  Future<void> pumpResults(
    WidgetTester tester,
    SearchState state, {
    void Function(Trip)? onSelect,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchResultsScreen(
          state: state,
          onSelectTrip: onSelect ?? (_) {},
        ),
      ),
    );
    // Let one-shot entrance delays (e.g. the date strip's 40 ms stagger)
    // elapse so no fake timer outlives the test.
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('P13 search results presentation', () {
    testWidgets('loading shows skeletons', (WidgetTester tester) async {
      final state = stateWith(status: SearchStatus.loading);
      addTearDown(state.dispose);
      await pumpResults(tester, state);
      expect(find.byType(SkeletonBlock), findsWidgets);
    });

    testWidgets('timeout error keeps its distinct copy', (
      WidgetTester tester,
    ) async {
      final state = stateWith(
        status: SearchStatus.error,
        errorKind: SearchErrorKind.timeout,
      );
      addTearDown(state.dispose);
      await pumpResults(tester, state);
      expect(find.text('Search failed'), findsOneWidget);
      expect(
        find.text(
          'The request timed out. Please check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('generic error keeps its distinct copy', (
      WidgetTester tester,
    ) async {
      final state = stateWith(
        status: SearchStatus.error,
        errorKind: SearchErrorKind.network,
      );
      addTearDown(state.dispose);
      await pumpResults(tester, state);
      expect(
        find.text('Something went wrong while searching. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('empty keeps the no-trains copy', (WidgetTester tester) async {
      final state = stateWith();
      addTearDown(state.dispose);
      await pumpResults(tester, state);
      expect(find.text('No trains on this route/date'), findsOneWidget);
      expect(find.text('Try another date or route.'), findsOneWidget);
    });

    testWidgets('trip card tap selects with press feedback', (
      WidgetTester tester,
    ) async {
      final state = stateWith(results: [trip('t1', 'Padma Express (Demo)')]);
      addTearDown(state.dispose);
      Trip? selected;
      await pumpResults(tester, state, onSelect: (t) => selected = t);
      await tester.pumpAndSettle();
      expect(find.byType(PressScale), findsWidgets);
      await tester.tap(find.text('Padma Express (Demo)'));
      await tester.pumpAndSettle();
      expect(selected?.id, 't1');
    });
  });
}

class _NeverApi implements SearchApi {
  @override
  Future<List<Station>> fetchStations() => Future.value(const <Station>[]);

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) => Future.value(const <Trip>[]);
}
