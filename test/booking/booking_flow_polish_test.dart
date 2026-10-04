import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/design/design.dart';
import 'package:railmate_bd/features/booking/passenger_ui/booking_review_screen.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_details_screen.dart';
import 'package:railmate_bd/features/booking/passenger_ui/passenger_form_state.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_screen.dart';
import 'package:railmate_bd/features/booking/seat_ui/seat_selection_state.dart';
import 'package:railmate_bd/features/bookings/booking_history.dart';
import 'package:railmate_bd/features/bookings/booking_history_screen.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/models/trip_seat.dart';

/// V4 P14–P18 widget polish pins: loading skeletons, P26 error/empty
/// states, and motion wrappers across the booking flow. Semantics are
/// covered by the state suites; this file only pins the presentation
/// contract (copy + affordances + state transitions).
void main() {
  Trip demoTrip() => Trip(
    id: 't-polish',
    trainName: 'Polish Express (Demo)',
    originStationId: 'o',
    destinationStationId: 'd',
    departureAt: DateTime(2026, 10, 5, 7, 0),
    arrivalAt: DateTime(2026, 10, 5, 12, 30),
    fareBdt: 500,
    active: true,
  );

  List<TripSeat> demoSeats() => [
    const TripSeat(id: 't-A1', tripId: 't-polish', seatCode: 'A1'),
    const TripSeat(id: 't-A2', tripId: 't-polish', seatCode: 'A2'),
  ];

  Future<void> pumpSeat(WidgetTester tester, SeatSelectionState state) =>
      tester.pumpWidget(
        MaterialApp(
          home: SeatSelectionScreen(
            trip: demoTrip(),
            state: state,
            onContinue: (_) {},
          ),
        ),
      );

  group('P14 seat selection polish', () {
    testWidgets('loading shows a skeleton, not a bare spinner', (
      WidgetTester tester,
    ) async {
      final gate = Completer<List<TripSeat>>();
      final state = SeatSelectionState(
        tripId: 't-polish',
        fetchSeats: (_) => gate.future,
      );
      addTearDown(state.dispose);
      await pumpSeat(tester, state);
      // The post-frame load has started and the fetch is still pending:
      // the skeleton stands in for the grid.
      await tester.pump();
      expect(find.byType(SkeletonBlock), findsWidgets);
      gate.complete(demoSeats());
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBlock), findsNothing);
      expect(find.text('A1'), findsOneWidget);
    });

    testWidgets('error shows ErrorState copy with a working retry', (
      WidgetTester tester,
    ) async {
      var calls = 0;
      final state = SeatSelectionState(
        tripId: 't-polish',
        fetchSeats: (_) async {
          calls++;
          if (calls == 1) throw Exception('boom');
          return demoSeats();
        },
      );
      addTearDown(state.dispose);
      await pumpSeat(tester, state);
      await tester.pumpAndSettle();
      expect(find.text('Could not load seats'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('A1'), findsOneWidget);
    });

    testWidgets('empty shows the EmptyState copy', (WidgetTester tester) async {
      final state = SeatSelectionState(
        tripId: 't-polish',
        fetchSeats: (_) async => const <TripSeat>[],
      );
      addTearDown(state.dispose);
      await pumpSeat(tester, state);
      await tester.pumpAndSettle();
      expect(find.text('No seats available for this trip'), findsOneWidget);
    });

    testWidgets('available seat tap selects with press feedback', (
      WidgetTester tester,
    ) async {
      final state = SeatSelectionState(
        tripId: 't-polish',
        fetchSeats: (_) async => demoSeats(),
      );
      addTearDown(state.dispose);
      await pumpSeat(tester, state);
      await tester.pumpAndSettle();
      await tester.tap(find.text('A1'));
      await tester.pump();
      expect(state.selectedSeatCodes, <String>['A1']);
      expect(find.text('Selected Seats (1)'), findsOneWidget);
      expect(find.byType(PressScale), findsWidgets);
    });
  });

  group('P15 passenger/review presentation', () {
    PassengerFormState validForm() {
      final form = PassengerFormState(
        seatCodes: const <String>['A1'],
        fareBdt: 500,
      );
      form
        ..updateName(0, 'Tanvir Ahmed')
        ..updateType(0, PassengerType.adult)
        ..setContactMobile('01712345678');
      return form;
    }

    testWidgets('passenger screen shows stepper, tabs and continue', (
      WidgetTester tester,
    ) async {
      final form = validForm();
      addTearDown(form.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PassengerDetailsScreen(formState: form, onContinue: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Passenger Details'), findsOneWidget);
      expect(find.text('Passengers'), findsOneWidget);
      expect(find.text('Passenger 1'), findsOneWidget);
      expect(find.byType(AnimatedSwap), findsWidgets);
    });

    testWidgets('review enables confirm only after accepting terms', (
      WidgetTester tester,
    ) async {
      final form = validForm();
      addTearDown(form.dispose);
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BookingReviewScreen(
            formState: form,
            onEditJourney: () {},
            onEditPassengers: () {},
            onConfirm: () => confirmed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The confirm button sits at the end of the ListView (below the fold
      // and outside the cache extent until scrolled): drag first.
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      final Finder button = find.text('Confirm Booking');
      expect(button, findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(of: button, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });
  });

  group('P18 booking history states', () {
    BookingHistoryRepository repo({
      required FetchBookingRows fetch,
      required CancelBookingRpc cancel,
    }) => BookingHistoryRepository(fetchRows: fetch, cancelRpc: cancel);

    Map<String, dynamic> row(String id, String status) => <String, dynamic>{
      'id': id,
      'user_id': 'u1',
      'trip_id': 'trip-1',
      'status': status,
      'total_fare_bdt': 1000,
      'created_at': '2026-10-01T10:00:00Z',
      'cancelled_at': status == 'CANCELLED' ? '2026-10-02T10:00:00Z' : null,
    };

    Future<void> pumpHistory(
      WidgetTester tester,
      BookingHistoryRepository repository,
    ) => tester.pumpWidget(
      MaterialApp(
        home: BookingHistoryScreen(repository: repository, ownerId: 'u1'),
      ),
    );

    testWidgets('loading shows skeletons, then the booking card', (
      WidgetTester tester,
    ) async {
      final repository = repo(
        fetch: (_) async => [row('b1', 'CONFIRMED')],
        cancel: ({required String ownerId, required String bookingId}) async =>
            true,
      );
      await pumpHistory(tester, repository);
      expect(find.byType(SkeletonBlock), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBlock), findsNothing);
      expect(find.text('Ref: b1'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsOneWidget);
    });

    testWidgets('error keeps the retry copy', (WidgetTester tester) async {
      final repository = repo(
        fetch: (_) async => throw Exception('down'),
        cancel: ({required String ownerId, required String bookingId}) async =>
            true,
      );
      await pumpHistory(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('Could not load bookings.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('empty keeps the demo wording', (WidgetTester tester) async {
      final repository = repo(
        fetch: (_) async => const <Map<String, dynamic>>[],
        cancel: ({required String ownerId, required String bookingId}) async =>
            true,
      );
      await pumpHistory(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('No bookings yet'), findsOneWidget);
    });

    testWidgets('cancel confirm dialog cancels without a second ask', (
      WidgetTester tester,
    ) async {
      var cancels = 0;
      final repository = repo(
        fetch: (_) async => [row('b1', 'CONFIRMED')],
        cancel: ({required String ownerId, required String bookingId}) async {
          cancels++;
          return true;
        },
      );
      await pumpHistory(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel whole booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel booking?'), findsOneWidget);
      await tester.tap(find.text('Cancel booking').last);
      await tester.pumpAndSettle();
      expect(cancels, 1);
      expect(find.text('Booking cancelled (demo).'), findsOneWidget);
    });
  });
}
