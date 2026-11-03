/// A03 — phone OTP repository behind an injectable client (RailMate BD).
///
/// [PhoneAuthRepository] validates Bangladeshi E.164 numbers (`+880...`),
/// enforces 6-digit codes and maps server rate-limit failures to
/// [PhoneAuthErrorKind.rateLimited] so the UI can message them distinctly.
///
/// Production wiring (teacher final gate, 2026-11-03): the app composes
/// [SupabasePhoneOtpClient] from the initialized client, so the Verify screen's
/// phone action reaches a real server-backed OTP flow. Whether a live SMS is
/// actually delivered still depends on the hosted Supabase project having an
/// SMS provider configured (owner-side, Handoff 02); when it is not, the
/// request fails with honest copy and never falls back to a fake token.
/// [FakePhoneOtpClient] remains test/demo-only and is never composed in
/// production.
library;

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../auth_repository.dart';

/// Client-side cooldown between OTP requests, surfaced as a resend timer.
const Duration kPhoneOtpResendCooldown = Duration(seconds: 30);

/// Distinct failure kinds for phone OTP; server rate limiting is its own
/// kind so the UI can message it distinctly from wrong codes or bad input.
enum PhoneAuthErrorKind {
  /// Phone number is not a valid Bangladeshi E.164 number.
  invalidPhone,

  /// Code is not 6 digits, or the server rejected it.
  invalidCode,

  /// Client resend cooldown hit, or the server refused with a rate limit.
  rateLimited,

  /// Transport/server failure that is not a rate limit.
  network,

  /// Anything else (e.g. verification returned no session).
  unknown,
}

/// Safe-to-display phone-OTP failure. Never carries tokens or secrets.
class PhoneAuthException implements Exception {
  /// Machine-readable failure kind.
  final PhoneAuthErrorKind kind;

  /// Human-readable message, safe to show in the UI.
  final String message;

  const PhoneAuthException(this.kind, this.message);

  @override
  String toString() => 'PhoneAuthException($kind): $message';
}

/// Injectable phone-OTP backend.
///
/// Production: [SupabasePhoneOtpClient]. Tests/demo: [FakePhoneOtpClient].
/// No implementation may send a live SMS except [SupabasePhoneOtpClient]
/// on explicit user action after provider approval (currently BLOCKED).
abstract class PhoneOtpClient {
  /// Requests a one-time code for [phone] (E.164, e.g. `+8801712345678`).
  Future<void> requestOtp(String phone);

  /// Verifies the 6-digit [token] for [phone]. Returns the verified user.
  Future<AuthUser> verifyOtp({required String phone, required String token});
}

/// Repository wrapping phone OTP behind the injectable [PhoneOtpClient].
class PhoneAuthRepository {
  /// Backing OTP client (real Supabase adapter or test/demo fake).
  final PhoneOtpClient client;

  /// Client-side resend cooldown enforced via [PhoneState.resendAt].
  final Duration resendCooldown;

  const PhoneAuthRepository({
    required this.client,
    this.resendCooldown = kPhoneOtpResendCooldown,
  });

  /// True when this repository is backed by the test/demo fake. Production
  /// composition always uses [SupabasePhoneOtpClient], so UI surfaces use
  /// this to decide whether a demo-only notice is honest.
  bool get isDemo => client is FakePhoneOtpClient;

  /// Bangladeshi mobile in E.164: `+880 1X` + 8 digits, X in 3–9.
  static final RegExp _bdE164 = RegExp(r'^\+8801[3-9]\d{8}$');

  /// Normalises user input to E.164: trims, drops spaces/dashes/brackets,
  /// and expands local `01XXXXXXXXX` / `8801XXXXXXXXX` to `+8801XXXXXXXXX`.
  static String normalizePhone(String raw) {
    String digits = raw.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.startsWith('0') && digits.length == 11) {
      digits = '+880${digits.substring(1)}';
    } else if (digits.startsWith('880') && digits.length == 13) {
      digits = '+$digits';
    }
    return digits;
  }

  /// True when [raw] normalises to a valid Bangladeshi E.164 number.
  static bool isValidPhone(String raw) => _bdE164.hasMatch(normalizePhone(raw));

  /// Throws [PhoneAuthException] with [PhoneAuthErrorKind.invalidPhone]
  /// when [raw] is not a valid Bangladeshi E.164 number.
  static void requirePhone(String raw) {
    if (!isValidPhone(raw)) {
      throw const PhoneAuthException(
        PhoneAuthErrorKind.invalidPhone,
        'Enter a valid Bangladeshi mobile number, e.g. +880 1712 345678.',
      );
    }
  }

  /// Throws [PhoneAuthException] with [PhoneAuthErrorKind.invalidCode]
  /// when [token] is not a 6-digit code.
  static void requireToken(String token) {
    final String code = token.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      throw const PhoneAuthException(
        PhoneAuthErrorKind.invalidCode,
        'Verification code must be 6 digits.',
      );
    }
  }

  /// Heuristic mapping of a backend failure to a rate limit: matches 429 /
  /// "rate" / "too many" / "try again later" / Supabase's "only request
  /// this once every ..." guard. Anything else maps to `network`.
  static bool isRateLimitFailure(Object error) {
    final String message = error.toString().toLowerCase();
    return message.contains('rate') ||
        message.contains('too many') ||
        message.contains('429') ||
        message.contains('try again later') ||
        message.contains('only request this once every');
  }

  /// Requests an OTP for [rawPhone] after E.164 validation.
  /// Throws [PhoneAuthException]; rate limits surface distinctly as
  /// [PhoneAuthErrorKind.rateLimited].
  Future<void> requestOtp(String rawPhone) async {
    requirePhone(rawPhone);
    try {
      await client.requestOtp(normalizePhone(rawPhone));
    } on PhoneAuthException {
      rethrow;
    } catch (e) {
      if (isRateLimitFailure(e)) {
        throw const PhoneAuthException(
          PhoneAuthErrorKind.rateLimited,
          'Too many attempts. Please wait a little while before trying again.',
        );
      }
      // Consumer gate: never interpolate the raw backend error.
      throw const PhoneAuthException(
        PhoneAuthErrorKind.network,
        'Could not send the code. Check your connection and try again.',
      );
    }
  }

  /// Verifies the 6-digit [token] for [rawPhone]. Returns the verified
  /// [AuthUser] (phone set; email empty for phone-only sessions).
  /// Throws [PhoneAuthException]; rate limits surface distinctly as
  /// [PhoneAuthErrorKind.rateLimited].
  Future<AuthUser> verifyOtp({
    required String rawPhone,
    required String token,
  }) async {
    requirePhone(rawPhone);
    requireToken(token);
    try {
      return await client.verifyOtp(
        phone: normalizePhone(rawPhone),
        token: token.trim(),
      );
    } on PhoneAuthException {
      rethrow;
    } catch (e) {
      if (isRateLimitFailure(e)) {
        throw const PhoneAuthException(
          PhoneAuthErrorKind.rateLimited,
          'Too many attempts. Please wait a little while before trying again.',
        );
      }
      // Consumer gate: never interpolate the raw backend error.
      throw const PhoneAuthException(
        PhoneAuthErrorKind.network,
        "That code didn't work. Check it and try again.",
      );
    }
  }
}

/// Production [PhoneOtpClient] backed by `Supabase.instance.client.auth`.
///
/// Two supported Supabase flows, chosen by whether a session already exists:
///
/// * Signed in (the normal Verify-screen case) — the number is *attached to
///   the existing account*: `updateUser(UserAttributes(phone:))` sends the
///   code and `verifyOTP(type: OtpType.phoneChange, phone:, token:)` confirms
///   it. This never swaps the signed-in identity for a phone-only user.
/// * No session — a genuine phone sign-in lane: `signInWithOtp(phone:)` sends
///   the code and `verifyOTP(type: OtpType.sms, phone:, token:)` returns the
///   session/user for that number.
///
/// Publishable (anon) key only — never a service-role key. No fake token, no
/// fallback: if the hosted project has no SMS provider, the call fails and the
/// screen shows honest copy. Live delivery is owner-side configuration.
class SupabasePhoneOtpClient implements PhoneOtpClient {
  /// Supabase client. Defaults to the global instance initialized at app
  /// startup; injectable for tests that need a shaped client.
  final SupabaseClient supabase;

  /// True when the pending code belongs to the `phone_change` flow (an OTP
  /// for the currently signed-in account), false for the `sms` sign-in lane.
  bool _changeFlow = false;

  SupabasePhoneOtpClient({SupabaseClient? supabase})
    : supabase = supabase ?? Supabase.instance.client;

  @override
  Future<void> requestOtp(String phone) async {
    if (supabase.auth.currentSession != null) {
      await supabase.auth.updateUser(UserAttributes(phone: phone));
      _changeFlow = true;
    } else {
      await supabase.auth.signInWithOtp(phone: phone);
      _changeFlow = false;
    }
  }

  @override
  Future<AuthUser> verifyOtp({
    required String phone,
    required String token,
  }) async {
    final AuthResponse response = await supabase.auth.verifyOTP(
      type: _changeFlow ? OtpType.phoneChange : OtpType.sms,
      token: token,
      phone: phone,
    );
    final User? user = response.session?.user ?? response.user;
    if (user == null) {
      throw const PhoneAuthException(
        PhoneAuthErrorKind.unknown,
        'Verification returned no session. Try resending the code.',
      );
    }
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      emailConfirmed: true,
      phone: user.phone ?? phone,
    );
  }
}

/// In-memory [PhoneOtpClient] double for widget/unit tests ONLY.
///
/// Sends no SMS. [requestOtp] only counts requests (and can simulate a
/// server 429 via [failRateLimitAfter]); [verifyOtp] accepts [demoCode].
/// Never composed in production (`AppDependencies.create` uses
/// [SupabasePhoneOtpClient]); surfaces that use this fake show a demo-only
/// notice instead of claiming live SMS.
class FakePhoneOtpClient implements PhoneOtpClient {
  /// Code accepted by [verifyOtp]. Defaults to a fixed demo value so tests
  /// and reviewers can drive the flow deterministically.
  String demoCode;

  /// Number of [requestOtp] calls observed.
  int requests = 0;

  /// When set, requests after the Nth throw a rate-limit failure,
  /// simulating a server 429 for negative-path tests.
  int? failRateLimitAfter;

  FakePhoneOtpClient({this.demoCode = '123456', this.failRateLimitAfter});

  @override
  Future<void> requestOtp(String phone) async {
    requests++;
    if (failRateLimitAfter != null && requests > failRateLimitAfter!) {
      throw const PhoneAuthException(
        PhoneAuthErrorKind.rateLimited,
        'Too many attempts (demo limit). Please wait before trying again.',
      );
    }
  }

  @override
  Future<AuthUser> verifyOtp({
    required String phone,
    required String token,
  }) async {
    if (token != demoCode) {
      throw const PhoneAuthException(
        PhoneAuthErrorKind.invalidCode,
        'Incorrect code. This demo build accepts the demo code only.',
      );
    }
    return AuthUser(
      id: 'demo-phone-user',
      email: '',
      emailConfirmed: true,
      phone: phone,
    );
  }
}
