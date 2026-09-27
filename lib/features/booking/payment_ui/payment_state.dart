import 'package:flutter/foundation.dart';

/// Terminal-aware outcome of the simulated payment.
enum PaymentStatus {
  /// Nothing attempted yet (or reset for a fresh attempt).
  idle,

  /// A simulation is in flight; duplicate taps must be ignored.
  processing,

  /// Simulated success: exactly one charge intent + one booking intent exist.
  succeeded,

  /// Simulated failure: no charge intent and no booking intent exist.
  failed,

  /// Provider returned an unrecognized payload: outcome unknown until
  /// [reconcileSucceeded]/[reconcileFailed] resolves it by [requestId].
  unknown,
}

/// Simulated payment state machine for packet B06 (APP-BOOK).
///
/// Contract:
/// * No real financial integration and no credential collection — this class
///   holds only the idempotency key, fare snapshot and outcome flags.
/// * [simulateSuccess] creates exactly one charge intent and marks a booking
///   intent. Any further tap after [PaymentStatus.succeeded] (or while
///   [PaymentStatus.processing]) is ignored and returns `false`, so a
///   duplicate tap can never create a second charge intent.
/// * [simulateFailure] creates no booking intent and no charge intent.
/// * [simulateUnknownResponse] records [PaymentStatus.unknown] with no
///   booking intent; [reconcileSucceeded]/[reconcileFailed] later resolve it
///   against the same [requestId] without ever creating a second charge
///   intent.
///
/// The host (booking flow) creates and owns this object and passes it into
/// the payment screen; the screen never creates, replaces or disposes it.
/// Fare numbers are a snapshot taken from B05's `PassengerFormState`
/// (`fareBreakdown`/`totalBdt`) at construction time.
class PaymentState extends ChangeNotifier {
  /// Stable idempotency key for this payment attempt. Retries and
  /// reconciliation reuse it; the booking lane keys server-side
  /// idempotency on it so a retry never double-books.
  final String requestId;

  /// Total payable in BDT snapshotted from `PassengerFormState.totalBdt`.
  final int totalBdt;

  /// Fare numbers snapshotted from `PassengerFormState.fareBreakdown`.
  final Map<String, int> fareBreakdown;

  PaymentStatus _status = PaymentStatus.idle;

  /// Number of charge intents ever created. Invariant: never exceeds 1.
  int _chargeIntentCount = 0;

  /// True only after a simulated success (or a reconcile-to-success).
  bool _bookingIntentCreated = false;

  /// Creates state for one payment attempt.
  ///
  /// Pass [requestId] explicitly in tests to assert idempotent replay;
  /// otherwise a unique simulation key is generated. Throws
  /// [ArgumentError] when [totalBdt] is negative.
  PaymentState({
    String? requestId,
    required this.totalBdt,
    required Map<String, int> fareBreakdown,
  }) : requestId = requestId ?? _newRequestId(),
       fareBreakdown = Map<String, int>.unmodifiable(fareBreakdown) {
    if (totalBdt < 0) {
      throw ArgumentError.value(totalBdt, 'totalBdt', 'Must be >= 0');
    }
  }

  /// Current outcome.
  PaymentStatus get status => _status;

  /// Charge intents created so far; never exceeds 1 (idempotency guard).
  int get chargeIntentCount => _chargeIntentCount;

  /// True only when a booking intent may proceed to the booking lane.
  bool get bookingIntentCreated => _bookingIntentCreated;

  /// True for [PaymentStatus.succeeded], [PaymentStatus.failed] and
  /// [PaymentStatus.unknown] outcomes that need no further simulation tap
  /// ([PaymentStatus.unknown] still needs reconciliation, not a re-tap).
  bool get isSettled =>
      _status == PaymentStatus.succeeded ||
      _status == PaymentStatus.failed ||
      _status == PaymentStatus.unknown;

  /// Simulates a successful payment.
  ///
  /// Creates the single charge intent and the booking intent, then moves to
  /// [PaymentStatus.succeeded]. Returns `false` without changing anything
  /// when already [PaymentStatus.processing] or [PaymentStatus.succeeded]
  /// (duplicate-tap guard).
  bool simulateSuccess() {
    if (_status == PaymentStatus.processing ||
        _status == PaymentStatus.succeeded) {
      return false;
    }
    _status = PaymentStatus.processing;
    notifyListeners();
    if (_chargeIntentCount == 0) {
      _chargeIntentCount = 1;
    }
    _bookingIntentCreated = true;
    _status = PaymentStatus.succeeded;
    notifyListeners();
    return true;
  }

  /// Simulates a failed payment.
  ///
  /// Creates no charge intent and no booking intent, then moves to
  /// [PaymentStatus.failed]. Returns `false` without changing anything when
  /// already [PaymentStatus.processing] or [PaymentStatus.succeeded].
  /// A later retry with [simulateSuccess] reuses the same [requestId].
  bool simulateFailure() {
    if (_status == PaymentStatus.processing ||
        _status == PaymentStatus.succeeded) {
      return false;
    }
    _status = PaymentStatus.processing;
    notifyListeners();
    _status = PaymentStatus.failed;
    notifyListeners();
    return true;
  }

  /// Records an unrecognized provider response.
  ///
  /// Creates no booking intent. Returns `false` without changing anything
  /// when already [PaymentStatus.processing] or [PaymentStatus.succeeded].
  bool simulateUnknownResponse() {
    if (_status == PaymentStatus.processing ||
        _status == PaymentStatus.succeeded) {
      return false;
    }
    _status = PaymentStatus.processing;
    notifyListeners();
    _status = PaymentStatus.unknown;
    notifyListeners();
    return true;
  }

  /// Reconciles an [PaymentStatus.unknown] outcome as success, keyed by
  /// [requestId].
  ///
  /// Reuses the single charge-intent slot (creates it only when none
  /// exists) so reconciliation never produces a second charge intent.
  /// Returns `false` unless the current status is [PaymentStatus.unknown].
  bool reconcileSucceeded() {
    if (_status != PaymentStatus.unknown) return false;
    if (_chargeIntentCount == 0) {
      _chargeIntentCount = 1;
    }
    _bookingIntentCreated = true;
    _status = PaymentStatus.succeeded;
    notifyListeners();
    return true;
  }

  /// Reconciles an [PaymentStatus.unknown] outcome as failure, keyed by
  /// [requestId]. Creates no booking intent. Returns `false` unless the
  /// current status is [PaymentStatus.unknown].
  bool reconcileFailed() {
    if (_status != PaymentStatus.unknown) return false;
    _status = PaymentStatus.failed;
    notifyListeners();
    return true;
  }

  static String _newRequestId() =>
      'pay-${DateTime.now().microsecondsSinceEpoch}';
}
