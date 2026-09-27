import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/bookings/booking_history.dart';

Map<String, dynamic> row(String id, String owner, String status) => {
  'id': id,
  'user_id': owner,
  'trip_id': 'trip-1',
  'status': status,
  'total_fare_bdt': 1440,
  'created_at': '2026-09-27T10:00:00Z',
};

BookingHistoryRepository repoWith({
  required List<Map<String, dynamic>> rows,
  required Future<bool> Function({
    required String ownerId,
    required String bookingId,
  })
  onCancel,
  List<Map<String, String>>? seenCalls,
}) {
  return BookingHistoryRepository(
    fetchRows: (_) async => rows,
    cancelRpc: ({required String ownerId, required String bookingId}) async {
      seenCalls?.add({'ownerId': ownerId, 'bookingId': bookingId});
      return onCancel(ownerId: ownerId, bookingId: bookingId);
    },
  );
}

void main() {
  test('owner-only cancel: rpc called with owner id', () async {
    final seen = <Map<String, String>>[];
    final repo = repoWith(
      rows: [row('b1', 'owner-1', 'CONFIRMED')],
      seenCalls: seen,
      onCancel: ({required String ownerId, required String bookingId}) async {
        expect(ownerId, 'owner-1');
        return true;
      },
    );
    expect(await repo.cancelOwned(ownerId: 'owner-1', bookingId: 'b1'), isTrue);
    expect(seen.single, {'ownerId': 'owner-1', 'bookingId': 'b1'});
  });

  test('non-owner cancel surfaces NOT_FOUND, no success', () async {
    final repo = repoWith(
      rows: [row('b1', 'owner-1', 'CONFIRMED')],
      onCancel: ({required String ownerId, required String bookingId}) async {
        throw Exception('NOT_FOUND');
      },
    );
    expect(
      () => repo.cancelOwned(ownerId: 'intruder', bookingId: 'b1'),
      throwsException,
    );
  });

  test('double-cancel idempotent: second cancel returns true', () async {
    var calls = 0;
    final repo = repoWith(
      rows: [row('b1', 'owner-1', 'CANCELLED')],
      onCancel: ({required String ownerId, required String bookingId}) async {
        calls++;
        return true; // server no-op success on already-cancelled
      },
    );
    expect(await repo.cancelOwned(ownerId: 'owner-1', bookingId: 'b1'), isTrue);
    expect(await repo.cancelOwned(ownerId: 'owner-1', bookingId: 'b1'), isTrue);
    expect(calls, 2);
  });

  test('list filters by owner; malformed skipped; newest first', () async {
    final repo = repoWith(
      rows: [
        row('foreign', 'owner-2', 'CONFIRMED'),
        {'no': 'id-at-all'},
        row('mine-old', 'owner-1', 'CONFIRMED'),
      ],
      onCancel: ({required String ownerId, required String bookingId}) async =>
          true,
    );
    final list = await repo.listOwned('owner-1');
    expect(list.map((b) => b.id), ['mine-old']);
  });

  test('blank ids throw before any RPC', () async {
    var called = false;
    final repo = repoWith(
      rows: [],
      onCancel: ({required String ownerId, required String bookingId}) async {
        called = true;
        return true;
      },
    );
    expect(
      () => repo.cancelOwned(ownerId: ' ', bookingId: 'b1'),
      throwsArgumentError,
    );
    expect(
      () => repo.cancelOwned(ownerId: 'owner-1', bookingId: ' '),
      throwsArgumentError,
    );
    expect(() => repo.listOwned(' '), throwsArgumentError);
    expect(called, isFalse);
  });
}
