/// Telegram phone-verification state (RailMate BD, P41).
///
/// Lifecycle: idle → creating → waiting → verified | expired | cancelled |
/// error. Nothing here claims a verified number: [status] only becomes
/// [TelegramStatus.verified] after the server row itself says `verified`, and
/// [maskedPhone] only ever holds the masked form stored by the webhook.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'telegram_verification_client.dart';

/// Lifecycle visible to the verification UI.
enum TelegramStatus {
  idle,
  creating,
  waiting,
  verified,
  expired,
  cancelled,
  error,
}

class TelegramVerificationState extends ChangeNotifier {
  final TelegramVerificationClient client;

  /// Opens the t.me deep link (injectable so tests never launch an app).
  final Future<void> Function(String url) openLink;

  final DateTime Function() clock;
  final Duration pollInterval;

  TelegramVerificationState({
    required this.client,
    required this.openLink,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 3),
  }) : clock = clock ?? DateTime.now;

  TelegramStatus _status = TelegramStatus.idle;
  String _challengeId = '';
  String _deepLink = '';
  String _maskedPhone = '';
  String _method = 'telegram_contact';
  String _errorMessage = '';
  DateTime? _expiresAt;
  Timer? _timer;

  TelegramStatus get status => _status;

  /// Masked number as stored by the backend; empty until verified.
  String get maskedPhone => _maskedPhone;

  /// Verification method recorded by the backend (`telegram_contact`).
  String get method => _method;

  /// Safe-to-display failure reason, or empty.
  String get errorMessage => _errorMessage;

  /// Deadline of the current challenge, if one is active.
  DateTime? get expiresAt => _expiresAt;

  /// True only after the server confirmed the contact share.
  bool get isVerified =>
      _status == TelegramStatus.verified && _maskedPhone.isNotEmpty;

  /// True while a challenge is being created.
  bool get isBusy => _status == TelegramStatus.creating;

  /// True when the user can start again after expiry/cancel/error.
  bool get canRetry =>
      _status == TelegramStatus.expired ||
      _status == TelegramStatus.cancelled ||
      _status == TelegramStatus.error;

  /// True when this state runs on the in-memory fake (tests only).
  bool get isDemo => client.isDemo;

  bool _restored = false;

  /// Loads an existing verification once (profile re-entry / app restart).
  ///
  /// Only an idle state is hydrated, and a failure is silent: the section then
  /// stays "not verified" rather than inventing a status.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    if (_status != TelegramStatus.idle) return;
    final TelegramChallengeStatus? existing;
    try {
      existing = await client.fetchLatestVerified();
    } catch (_) {
      return;
    }
    if (existing == null) return;
    if (existing.state != TelegramChallengeState.verified) return;
    if (existing.maskedPhone.isEmpty) return;
    _maskedPhone = existing.maskedPhone;
    _method = existing.method;
    _errorMessage = '';
    _status = TelegramStatus.verified;
    notifyListeners();
  }

  /// Creates a challenge, opens Telegram, then polls until a verdict arrives.
  Future<void> start() async {
    _stopTimer();
    _errorMessage = '';
    _maskedPhone = '';
    _status = TelegramStatus.creating;
    notifyListeners();

    try {
      final TelegramChallenge challenge = await client.createChallenge();
      _challengeId = challenge.id;
      _deepLink = challenge.deepLink;
      _expiresAt = challenge.expiresAt;
    } on TelegramVerificationException catch (e) {
      _fail(e.message);
      return;
    } catch (_) {
      _fail(
        'Could not start verification. Check your connection and try again.',
      );
      return;
    }

    try {
      await openLink(_deepLink);
    } catch (_) {
      // Telegram missing or blocked: the user can still open it manually.
      _fail('Could not open Telegram. Install it, then tap Try again.');
      return;
    }

    _status = TelegramStatus.waiting;
    notifyListeners();
    _startTimer();
  }

  /// One status check. Public so tests can drive the poller without timers.
  Future<void> pollOnce() async {
    if (_challengeId.isEmpty) return;
    if (_status != TelegramStatus.waiting) {
      return;
    }
    final TelegramChallengeStatus? result;
    try {
      result = await client.fetchStatus(_challengeId);
    } catch (_) {
      // Transient network trouble must not claim anything: keep waiting and
      // surface a soft error only when the challenge has also run out.
      if (_expiresAt != null && clock().isAfter(_expiresAt!)) {
        _stopTimer();
        _fail('Verification timed out. Start again when you are ready.');
      }
      return;
    }
    if (result == null) {
      _stopTimer();
      _setStatus(TelegramStatus.expired);
      return;
    }
    switch (result.state) {
      case TelegramChallengeState.verified:
        _stopTimer();
        _maskedPhone = result.maskedPhone;
        _method = result.method;
        _errorMessage = '';
        _setStatus(TelegramStatus.verified);
      case TelegramChallengeState.expired:
        _stopTimer();
        _setStatus(TelegramStatus.expired);
      case TelegramChallengeState.cancelled:
        _stopTimer();
        _setStatus(TelegramStatus.cancelled);
      case TelegramChallengeState.pending:
      case TelegramChallengeState.contactShared:
        if (_expiresAt != null && clock().isAfter(_expiresAt!)) {
          _stopTimer();
          _setStatus(TelegramStatus.expired);
        }
    }
  }

  /// Cancels the pending challenge (server + local state).
  Future<void> cancel() async {
    _stopTimer();
    if (_challengeId.isNotEmpty) {
      try {
        await client.cancel(_challengeId);
      } catch (_) {
        // Best effort; the row expires server-side regardless.
      }
    }
    _challengeId = '';
    _status = TelegramStatus.cancelled;
    notifyListeners();
  }

  /// Returns to idle so the section can be reused.
  void reset() {
    _stopTimer();
    _challengeId = '';
    _deepLink = '';
    _maskedPhone = '';
    _method = 'telegram_contact';
    _errorMessage = '';
    _expiresAt = null;
    _status = TelegramStatus.idle;
    notifyListeners();
  }

  void _startTimer() {
    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(pollOnce());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _fail(String message) {
    _stopTimer();
    _errorMessage = message;
    _status = TelegramStatus.error;
    notifyListeners();
  }

  void _setStatus(TelegramStatus next) {
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
