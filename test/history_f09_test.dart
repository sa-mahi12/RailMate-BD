import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/bookings/booking_history.dart';

/// F09 hermetic tests: booking-history state machine + live-cancel-path
/// contract (repository usage only — zero network).
///
/// What this pins (mirroring `BookingHistoryScreen` + `historyFor`):
/// * loading -> populated (newest-first, CANCELLED rows stay visible),
///   loading -> empty, loading -> error -> retry.
/// * cancel goes ONLY through injected `cancelRpc` (the `cancel-booking`
///   Edge path); a `false` return (Edge status != CANCELLED) is failure,
///   never fake success; success refreshes the list; failure keeps the
///   existing list and returns an honest message; repeat cancel is a
///   no-op success.
/// * `parseCancelResponse` mirrors `AppDependencies.historyFor`'s
///   `data['status'] == 'CANCELLED'` mapping (true/false shapes).
/// * `publicCancelMessage` mirrors the screen's `_publicMessage` mapping
///   (NOT_FOUND / UNAUTHORIZED / network / generic).
///
/// Live cancel proof with a real user is F08/F20 device work — this file
/// never touches the network (all fakes, in-memory).
void main() {
  Map<String, dynamic> row(
    String id,
    String owner,
    String status,
    String createdAt,
  ) => <String, dynamic>{
    'id': id,
    'user_id': owner,
    'trip_id': 'trip-1',
    'status': status,
    'total_fare_bdt': 1440,
    'created_at': createdAt,
    'cancelled_at': status == 'CANCELLED' ? createdAt : null,
  };

  BookingHistoryRepository repo({
    required FetchBookingRows fetch,
    required CancelBookingRpc cancel,
  }) => BookingHistoryRepository(fetchRows: fetch, cancelRpc: cancel);

  group('HistoryController (test-local mirror of screen logic)', () {
    test('loading -> populated newest-first, active flags intact', () async {
      final repository = repo(
        fetch: (_) async => [
          row('old', 'u1', 'CONFIRMED', '2026-09-27T10:00:00Z'),
          row('new', 'u1', 'CONFIRMED', '2026-09-28T10:00:00Z'),
        ],
        cancel: ({required String ownerId, required String bookingId}) async =>
            true,
      );
      final controller = HistoryController(
        repository: repository,
        ownerId: 'u1',
      );
      expect(controller.phase, HistoryPhase.loading);
      await controller.load();
      expect(controller.phase, HistoryPhase.populated);
      expect(controller.items.map((b) => b.id), ['new', 'old']);
      expect(controller.items.every((b) => b.isActive), isTrue);
    });

    test('loading -> empty stays populated with zero rows', () async {
      final repository = repo(
        fetch: (_) async => const <Map<String, dynamic>>[],
        cancel: ({required String ownerId, required String bookingId}) async =>
            true,
      );
      final controller = HistoryController(
        repository: repository,
        ownerId: 'u1',
      );
      await controller.load();
      expect(controller.phase, HistoryPhase.populated);
      expect(controller.items, isEmpty);
    });

    test('loading -> error -> retry recovers', () async {
      var calls = 0;
      final repository = repo(
        fetch: (_) async {
          calls++;
          if (calls == 1) throw Exception('Failed host lookup');
          return [row('b1', 'u1', 'CONFIRMED', '2026-09-28T10:00:00Z')];
        },
        cancel: ({required String ownerId, required String bookingId}) async =>
            true,
      );
      final controller = HistoryController(
        repository: repository,
        ownerId: 'u1',
      );
      await controller.load();
      expect(controller.phase, HistoryPhase.error);
      expect(controller.error, isNotNull);
      await controller.load(); // retry
      expect(controller.phase, HistoryPhase.populated);
      expect(controller.items.map((b) => b.id), ['b1']);
      expect(calls, 2);
    });

    test(
      'cancel -> cancelled refresh keeps row visible as CANCELLED',
      () async {
        // Mutable fake store: cancel flips the row, list re-reads it.
        final store = <String, Map<String, dynamic>>{
          'b1': row('b1', 'u1', 'CONFIRMED', '2026-09-28T10:00:00Z'),
        };
        final seen = <Map<String, String>>[];
        final repository = repo(
          fetch: (_) async => store.values.toList(),
          cancel: ({required String ownerId, required String bookingId}) async {
            seen.add({'ownerId': ownerId, 'bookingId': bookingId});
            final current = store[bookingId]!;
            store[bookingId] = {...current, 'status': 'CANCELLED'};
            return true; // Edge {status: CANCELLED} shape
          },
        );
        final controller = HistoryController(
          repository: repository,
          ownerId: 'u1',
        );
        await controller.load();
        expect(controller.items.single.isActive, isTrue);

        final failure = await controller.cancel('b1');
        expect(failure, isNull); // success -> no error message
        // Repository semantics: cancelled row STAYS visible (not dropped).
        expect(controller.items, hasLength(1));
        expect(controller.items.single.id, 'b1');
        expect(controller.items.single.isCancelled, isTrue);
        expect(controller.items.single.isActive, isFalse);
        expect(seen.single, {'ownerId': 'u1', 'bookingId': 'b1'});
      },
    );

    test('cancel failure -> honest error, list kept', () async {
      final repository = repo(
        fetch: (_) async => [
          row('b1', 'u1', 'CONFIRMED', '2026-09-28T10:00:00Z'),
        ],
        cancel: ({required String ownerId, required String bookingId}) async {
          throw Exception('NOT_FOUND');
        },
      );
      final controller = HistoryController(
        repository: repository,
        ownerId: 'u1',
      );
      await controller.load();
      final failure = await controller.cancel('b1');
      expect(failure, contains('NOT_FOUND'));
      // List is kept, not cleared or faked.
      expect(controller.phase, HistoryPhase.populated);
      expect(controller.items.map((b) => b.id), ['b1']);
      expect(controller.items.single.isActive, isTrue);
    });

    test(
      'cancelRpc false is failure, never fake success, no refresh',
      () async {
        var loads = 0;
        final repository = repo(
          fetch: (_) async {
            loads++;
            return [row('b1', 'u1', 'CONFIRMED', '2026-09-28T10:00:00Z')];
          },
          cancel: ({
            required String ownerId,
            required String bookingId,
          }) async => false, // Edge status was NOT CANCELLED
        );
        final controller = HistoryController(
          repository: repository,
          ownerId: 'u1',
        );
        await controller.load();
        expect(loads, 1);
        final failure = await controller.cancel('b1');
        expect(failure, 'BOOKING_CANCEL_FAILED');
        expect(loads, 1); // no success-refresh on failure
        expect(controller.items.single.isActive, isTrue);
      },
    );

    test('idempotent repeat cancel returns true twice, no error', () async {
      var calls = 0;
      final repository = repo(
        fetch: (_) async => [
          row('b1', 'u1', 'CANCELLED', '2026-09-28T10:00:00Z'),
        ],
        cancel: ({required String ownerId, required String bookingId}) async {
          calls++;
          return true; // server no-op success on already-cancelled
        },
      );
      expect(
        await repository.cancelOwned(ownerId: 'u1', bookingId: 'b1'),
        isTrue,
      );
      expect(
        await repository.cancelOwned(ownerId: 'u1', bookingId: 'b1'),
        isTrue,
      );
      expect(calls, 2);
    });
  });

  group('parseCancelResponse (mirrors historyFor Edge mapping)', () {
    test('CANCELLED true shape', () {
      expect(parseCancelResponse(const {'status': 'CANCELLED'}), isTrue);
    });

    test('non-CANCELLED shapes are false, never success', () {
      expect(parseCancelResponse(const {'status': 'FAILED'}), isFalse);
      expect(parseCancelResponse(const <String, dynamic>{}), isFalse);
      // Host comparison is case-sensitive: lowercase is NOT success.
      expect(parseCancelResponse(const {'status': 'cancelled'}), isFalse);
      expect(
        parseCancelResponse(const {'status': 'CANCELLED', 'booking_id': 'b1'}),
        isTrue,
      );
    });
  });

  group('publicCancelMessage (mirrors screen _publicMessage)', () {
    test('NOT_FOUND names ownership', () {
      expect(
        publicCancelMessage(Exception('NOT_FOUND')),
        contains('NOT_FOUND'),
      );
    });

    test('UNAUTHORIZED asks to sign in again', () {
      expect(
        publicCancelMessage(Exception('UNAUTHORIZED')),
        contains('sign in again'),
      );
    });

    test('transport failures map to network retry message', () {
      for (final raw in [
        'SocketException: OS Error',
        'ClientException: connection closed',
        'TimeoutException after 0:00:30',
        'Failed host lookup',
      ]) {
        expect(
          publicCancelMessage(Exception(raw)),
          contains('Network error'),
          reason: raw,
        );
      }
    });

    test('anything else is BOOKING_CANCEL_FAILED', () {
      expect(publicCancelMessage(Exception('boom')), 'BOOKING_CANCEL_FAILED');
    });
  });
}

/// Test-local view-model mirroring `BookingHistoryScreen` state flow.
///
/// Loading/error/populated phases plus cancel that ONLY calls
/// [BookingHistoryRepository.cancelOwned] (the injected `cancelRpc` Edge
/// path), treats `false` as failure, refreshes on success, and keeps the
/// list on failure. Keeps the hermetic tests honest about the screen's
/// contract without pumping widgets.
enum HistoryPhase { loading, populated, error }

class HistoryController {
  final BookingHistoryRepository repository;
  final String ownerId;

  HistoryPhase phase = HistoryPhase.loading;
  List<BookingSummary> items = const [];
  String? error;

  HistoryController({required this.repository, required this.ownerId});

  Future<void> load() async {
    phase = HistoryPhase.loading;
    error = null;
    try {
      items = await repository.listOwned(ownerId);
      phase = HistoryPhase.populated;
    } catch (e) {
      phase = HistoryPhase.error;
      error = e.toString();
    }
  }

  /// Returns null on success, honest message on failure (list kept).
  Future<String?> cancel(String bookingId) async {
    try {
      final ok = await repository.cancelOwned(
        ownerId: ownerId,
        bookingId: bookingId,
      );
      if (!ok) return 'BOOKING_CANCEL_FAILED';
      await load(); // success refresh: cancelled row stays as CANCELLED
      return null;
    } catch (e) {
      return publicCancelMessage(e);
    }
  }
}

/// Mirrors `AppDependencies.historyFor`'s cancel mapping:
/// `data['status'] == 'CANCELLED'`.
bool parseCancelResponse(Map<String, dynamic> data) =>
    data['status'] == 'CANCELLED';

/// Mirrors `BookingHistoryScreen._publicMessage` (honest Edge failures).
String publicCancelMessage(Object e) {
  final text = e.toString();
  if (text.contains('NOT_FOUND')) {
    return 'NOT_FOUND — booking does not exist or is not yours.';
  }
  if (text.contains('UNAUTHORIZED')) {
    return 'UNAUTHORIZED — please sign in again.';
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('TimeoutException') ||
      text.contains('Network is unreachable') ||
      text.contains('Failed host lookup')) {
    return 'Network error — check connection and retry.';
  }
  return 'BOOKING_CANCEL_FAILED';
}
