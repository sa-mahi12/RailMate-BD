/// A03 — phone OTP verification state (RailMate BD).
///
/// [PhoneState] is a [ChangeNotifier] holding the phone-verification
/// lifecycle: [PhoneStatus.idle] → [PhoneStatus.codeSent] →
/// [PhoneStatus.verifying] → [PhoneStatus.verified], with
/// [PhoneStatus.error] carrying [errorMessage] (safe to display — never
/// contains secrets) and [rateLimited] flagging cooldown/429 failures
/// distinctly. [resendAt] is the client-side resend cooldown deadline.
///
/// The verified user reuses [AuthUser] from `auth_repository.dart`
/// (read-only) with `phone` set; [isPhoneVerified] is the verification
/// status flag route guards should check for the phone lane.
library;

import 'package:flutter/foundation.dart';

import '../auth_repository.dart';
import 'phone_auth_repository.dart';

/// Lifecycle visible to the phone-verification UI.
enum PhoneStatus {
  /// No code requested yet (or number was reset).
  idle,

  /// A code was requested; awaiting the 6-digit token.
  codeSent,

  /// A verify call is in flight.
  verifying,

  /// The number verified successfully; see [user].
  verified,

  /// Last operation failed; see [errorMessage] and [rateLimited].
  error,
}

/// Session state for the phone-OTP slice.
class PhoneState extends ChangeNotifier {
  /// Backing repository (real Supabase adapter or test/demo fake).
  final PhoneAuthRepository repository;

  /// Clock used for the resend cooldown; injectable so tests can time-travel.
  final DateTime Function() clock;

  PhoneState({required this.repository, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  PhoneStatus _status = PhoneStatus.idle;
  String _phone = '';
  String _errorMessage = '';
  bool _rateLimited = false;
  bool _sending = false;
  DateTime? _resendAt;
  AuthUser? _user;

  /// Current lifecycle status.
  PhoneStatus get status => _status;

  /// Normalised E.164 number a code was sent to, or empty before request.
  String get phone => _phone;

  /// Last failure reason, or empty. Never contains secrets.
  String get errorMessage => _errorMessage;

  /// True when the last failure was a resend cooldown or server rate limit.
  bool get rateLimited => _rateLimited;

  /// Cooldown deadline for resending; null before the first request.
  DateTime? get resendAt => _resendAt;

  /// Verified phone user, or null until [PhoneStatus.verified].
  AuthUser? get user => _user;

  /// Verification status flag: true only after a successful phone verify.
  bool get isPhoneVerified => _status == PhoneStatus.verified && _user != null;

  /// True while a request/verify call is in flight.
  bool get isBusy => _sending || _status == PhoneStatus.verifying;

  /// True while a code is outstanding for [_phone] (code entry UI visible).
  bool get hasPendingCode =>
      _phone.isNotEmpty &&
      (_status == PhoneStatus.codeSent ||
          _status == PhoneStatus.verifying ||
          _status == PhoneStatus.error ||
          _status == PhoneStatus.verified);

  /// True when a (re)send is allowed right now.
  bool get canResend => _resendAt == null || !clock().isBefore(_resendAt!);

  /// Time left on the resend cooldown; zero when [canResend].
  Duration get resendRemaining {
    if (_resendAt == null) return Duration.zero;
    final Duration left = _resendAt!.difference(clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Requests a code for [rawPhone]. On success the status becomes
  /// [PhoneStatus.codeSent] and [resendAt] arms the cooldown; on failure
  /// [PhoneStatus.error] carries the reason.
  Future<void> requestCode(String rawPhone) async {
    _sending = true;
    _rateLimited = false;
    _errorMessage = '';
    notifyListeners();
    try {
      await repository.requestOtp(rawPhone);
      _phone = PhoneAuthRepository.normalizePhone(rawPhone);
      _user = null;
      _resendAt = clock().add(repository.resendCooldown);
      _setStatus(PhoneStatus.codeSent);
    } on PhoneAuthException catch (e) {
      _fail(e.message, rateLimited: e.kind == PhoneAuthErrorKind.rateLimited);
    } catch (e) {
      _fail('Could not send the code: $e');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Re-sends the code to the current [_phone], honouring the client-side
  /// cooldown: when [canResend] is false this records a cooldown error
  /// (flagged [rateLimited]) without touching the backend.
  Future<void> resend() async {
    if (_phone.isEmpty) {
      _fail('Enter your mobile number first.');
      notifyListeners();
      return;
    }
    if (!canResend) {
      _fail(
        'Resend available in ${_formatDuration(resendRemaining)}.',
        rateLimited: true,
      );
      notifyListeners();
      return;
    }
    await requestCode(_phone);
  }

  /// Submits the 6-digit [token] for the pending [_phone]. On success the
  /// status becomes [PhoneStatus.verified] with [user] set; on failure
  /// [PhoneStatus.error] carries the reason ([rateLimited] when throttled).
  Future<void> verifyCode(String token) async {
    if (_phone.isEmpty) {
      _fail('Send a code to your number first.');
      notifyListeners();
      return;
    }
    _setStatus(PhoneStatus.verifying);
    _rateLimited = false;
    _errorMessage = '';
    notifyListeners();
    try {
      final AuthUser verified = await repository.verifyOtp(
        rawPhone: _phone,
        token: token,
      );
      _user = verified;
      _errorMessage = '';
      _rateLimited = false;
      _setStatus(PhoneStatus.verified);
    } on PhoneAuthException catch (e) {
      _fail(e.message, rateLimited: e.kind == PhoneAuthErrorKind.rateLimited);
    } catch (e) {
      _fail('Verification failed: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Clears any displayed error without changing the verification flow.
  void clearError() {
    _errorMessage = '';
    _rateLimited = false;
    notifyListeners();
  }

  /// Resets to [PhoneStatus.idle] so the user can enter a different number.
  void reset() {
    _phone = '';
    _user = null;
    _resendAt = null;
    _errorMessage = '';
    _rateLimited = false;
    _sending = false;
    _setStatus(PhoneStatus.idle);
  }

  void _fail(String message, {bool rateLimited = false}) {
    _errorMessage = message;
    _rateLimited = rateLimited;
    _setStatus(PhoneStatus.error);
  }

  void _setStatus(PhoneStatus next) {
    _status = next;
    notifyListeners();
  }

  static String _formatDuration(Duration duration) {
    final int total = duration.inSeconds;
    final String minutes = (total ~/ 60).toString().padLeft(2, '0');
    final String seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
