import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/board/post/post.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/models/trip_seat.dart';
import 'package:railmate_bd/features/search/search_repository.dart';

/// F19 hermetic fakes (Worker E lane: `test/**` new files only).
///
/// Every fake is in-memory; no network, no platform channels, no secrets.
/// The only user-like values are fixed demo strings (`qa@example.com`,
/// `DEMO ...` train names).
class F19AuthClient implements AuthClient {
  AuthUser? stubUser;

  F19AuthClient({this.stubUser});

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async => stubUser;

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async => stubUser;

  @override
  Future<void> signOut() async {
    stubUser = null;
  }

  @override
  AuthUser? get currentUser => stubUser;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<AuthUser?> refreshSession() async => stubUser;

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async => stubUser;
}

/// In-memory [SearchApi]: preset stations/trips, never the network.
class F19SearchApi implements SearchApi {
  final List<Station> stations;
  final List<Trip> trips;

  F19SearchApi({required this.stations, required this.trips});

  @override
  Future<List<Station>> fetchStations() async => List<Station>.of(stations);

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) async => List<Trip>.of(trips);
}

/// Stub signed-in user for logged-in composition tests.
const AuthUser kF19StubUser = AuthUser(
  id: 'u-f19',
  email: 'qa@example.com',
  emailConfirmed: true,
  fullName: 'QA Engineer',
  username: 'qaeng',
);

/// Session state for composition tests. Logged-in goes through the real
/// [AuthState.signIn] path against [F19AuthClient] (no network).
Future<AuthState> f19AuthState({required bool loggedIn}) async {
  final AuthState auth = AuthState(
    repository: AuthRepository(
      client: F19AuthClient(stubUser: loggedIn ? kF19StubUser : null),
    ),
  );
  if (loggedIn) {
    await auth.signIn(email: 'qa@example.com', password: 'password123');
  }
  return auth;
}

/// Test composition under test: null client, so every backend closure fails
/// loudly with [StateError] instead of touching the network.
AppDependencies f19TestDeps({required AuthState auth, SearchApi? api}) {
  return AppDependencies.test(
    auth: auth,
    searchApi: api ?? F19SearchApi(stations: f19Stations(), trips: f19Trips()),
  );
}

List<Station> f19Stations() => const <Station>[
  Station(id: 's-dac', code: 'DAC', name: 'Dhaka'),
  Station(id: 's-cgp', code: 'CGP', name: 'Chattogram'),
];

List<Trip> f19Trips() {
  final DateTime dep = DateTime(2026, 10, 15, 8, 0);
  final DateTime arr = dep.add(const Duration(hours: 3, minutes: 45));
  return <Trip>[
    Trip(
      id: 't-padma',
      trainName: 'DEMO Padma Express',
      originStationId: 's-dac',
      destinationStationId: 's-cgp',
      departureAt: dep,
      arrivalAt: arr,
      fareBdt: 500,
      active: true,
    ),
    Trip(
      id: 't-silk',
      trainName: 'DEMO Silk City',
      originStationId: 's-dac',
      destinationStationId: 's-cgp',
      departureAt: dep.add(const Duration(hours: 2)),
      arrivalAt: arr.add(const Duration(hours: 2)),
      fareBdt: 650,
      active: true,
    ),
  ];
}

/// Fake seat inventory: one available, one demo-held (disabled grey),
/// one really-booked (disabled orange), plus spares.
List<TripSeat> f19Seats() => const <TripSeat>[
  TripSeat(id: 's-A1', tripId: 't-padma', seatCode: 'A1'),
  TripSeat(id: 's-A2', tripId: 't-padma', seatCode: 'A2', demoReserved: true),
  TripSeat(id: 's-A3', tripId: 't-padma', seatCode: 'A3'),
  TripSeat(id: 's-B1', tripId: 't-padma', seatCode: 'B1', bookingId: 'bk-9'),
  TripSeat(id: 's-B2', tripId: 't-padma', seatCode: 'B2'),
];

List<Post> f19Posts() => <Post>[
  Post(
    id: 'p1',
    userId: 'u-f19',
    body: 'Morning run to DAC was smooth. DEMO.',
    createdAt: DateTime(2026, 9, 28, 10),
  ),
  Post(
    id: 'p2',
    userId: 'u-f19',
    body: 'CGP platform tips. DEMO.',
    createdAt: DateTime(2026, 9, 27, 10),
  ),
];

Map<String, dynamic> f19BookingRow({
  String id = 'b1',
  String owner = 'u-f19',
  String status = 'CONFIRMED',
}) => <String, dynamic>{
  'id': id,
  'user_id': owner,
  'trip_id': 't-padma',
  'status': status,
  'total_fare_bdt': 540,
  'created_at': '2026-09-28T10:00:00Z',
  'cancelled_at': null,
};

/// Pumps one real [Route] object (built by `AppRoutes.onGenerateRoute`) on
/// top of a bare host, mirroring how a tab [Navigator] pushes it.
Future<void> pumpAppRoute(WidgetTester tester, Route<dynamic> route) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(Navigator.of(context).push(route));
          });
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
