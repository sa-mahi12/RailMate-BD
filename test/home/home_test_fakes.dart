/// P10 test doubles: hermetic fakes only (no network, no platform channels).
library;

import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/search/models/station.dart';
import 'package:railmate_bd/features/search/models/trip.dart';
import 'package:railmate_bd/features/search/search_repository.dart';

const Station dhaka = Station(
  id: '11111111-1111-4111-8111-111111111111',
  code: 'DAC',
  name: 'Dhaka',
);
const Station chattogram = Station(
  id: '22222222-2222-4222-8222-222222222222',
  code: 'CGP',
  name: 'Chattogram',
);
const Station sylhet = Station(
  id: '33333333-3333-4333-8333-333333333333',
  code: 'SYL',
  name: 'Sylhet',
);
const Station rajshahi = Station(
  id: '44444444-4444-4444-8444-444444444444',
  code: 'RJH',
  name: 'Rajshahi',
);
const Station khulna = Station(
  id: '88888888-8888-4888-8888-888888888888',
  code: 'KHL',
  name: 'Khulna',
);

Trip demoTrip(String id, DateTime departureAt) =>
    Trip.fromMap(<String, dynamic>{
      'id': id,
      'train_name': 'Subarna Express (Demo)',
      'origin_station_id': dhaka.id,
      'destination_station_id': chattogram.id,
      'departure_at': departureAt.toIso8601String(),
      'arrival_at': departureAt.add(const Duration(hours: 5)).toIso8601String(),
      'fare_bdt': 625,
      'active': true,
    });

/// In-memory [SearchApi]; counts station loads and search calls.
class FakeSearchApi implements SearchApi {
  FakeSearchApi({this.stations = const <Station>[], this.stationError});

  final List<Station> stations;
  final Object? stationError;
  int stationLoads = 0;
  int searches = 0;

  @override
  Future<List<Station>> fetchStations() async {
    stationLoads++;
    if (stationError != null) throw stationError!;
    return stations;
  }

  @override
  Future<List<Trip>> searchTrips({
    required String originId,
    required String destinationId,
    required DateTime date,
  }) async {
    searches++;
    return <Trip>[
      demoTrip('trip-$originId', date.add(const Duration(hours: 8))),
    ];
  }
}

/// Minimal [AuthClient] fake whose session can be signed in or out.
class FakeAuthClient implements AuthClient {
  FakeAuthClient({this.user});

  AuthUser? user;

  @override
  Future<AuthUser?> refreshSession() async => user;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  AuthUser? get currentUser => user;

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async => user;

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async => user;

  @override
  Future<void> signOut() async => user = null;

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async => user;

  @override
  Future<bool> requestPasswordReset(String email) async => true;

  @override
  Future<void> updatePassword({required String newPassword}) async {}
}

/// Signed-in [AuthState] with a restored session (real `restore()` path).
Future<AuthState> signedInAuth({String? fullName, String? username}) async {
  final FakeAuthClient client = FakeAuthClient(
    user: AuthUser(
      id: 'user-1',
      email: 'traveller@example.com',
      emailConfirmed: true,
      fullName: fullName,
      username: username,
    ),
  );
  final AuthState auth = AuthState(repository: AuthRepository(client: client));
  await auth.restore();
  return auth;
}

/// Signed-out [AuthState].
Future<AuthState> signedOutAuth() async {
  final AuthState auth = AuthState(
    repository: AuthRepository(client: FakeAuthClient()),
  );
  await auth.restore();
  return auth;
}
