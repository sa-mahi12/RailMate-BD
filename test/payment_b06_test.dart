import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/booking/payment_ui/payment_state.dart';

void main() {
  test(
    'success creates exactly one charge+booking intent; duplicate tap ignored',
    () {
      final s = PaymentState(
        requestId: 'req-1',
        totalBdt: 1440,
        fareBreakdown: const {'total': 1440},
      );
      expect(s.simulateSuccess(), isTrue);
      expect(s.status, PaymentStatus.succeeded);
      expect(s.chargeIntentCount, 1);
      expect(s.bookingIntentCreated, isTrue);
      expect(s.simulateSuccess(), isFalse); // duplicate tap
      expect(s.chargeIntentCount, 1);
    },
  );
  test(
    'fail creates no booking intent; retry with same request id succeeds once',
    () {
      final s = PaymentState(
        requestId: 'req-2',
        totalBdt: 1440,
        fareBreakdown: const {'total': 1440},
      );
      expect(s.simulateFailure(), isTrue);
      expect(s.bookingIntentCreated, isFalse);
      expect(s.chargeIntentCount, 0);
      expect(s.simulateSuccess(), isTrue);
      expect(s.requestId, 'req-2');
      expect(s.chargeIntentCount, 1);
    },
  );
  test('unknown reconciles by request id without a second charge intent', () {
    final s = PaymentState(
      requestId: 'req-3',
      totalBdt: 1440,
      fareBreakdown: const {'total': 1440},
    );
    expect(s.simulateUnknownResponse(), isTrue);
    expect(s.bookingIntentCreated, isFalse);
    expect(s.reconcileSucceeded(), isTrue);
    expect(s.chargeIntentCount, 1);
    expect(s.simulateSuccess(), isFalse); // post-reconcile duplicate
    expect(s.chargeIntentCount, 1);
  });
  test('negatives: reconcile without unknown fails; negative total throws', () {
    final s = PaymentState(
      requestId: 'req-4',
      totalBdt: 0,
      fareBreakdown: const {'total': 0},
    );
    expect(s.reconcileSucceeded(), isFalse);
    expect(s.reconcileFailed(), isFalse);
    expect(
      () => PaymentState(totalBdt: -1, fareBreakdown: const {}),
      throwsArgumentError,
    );
  });
}
