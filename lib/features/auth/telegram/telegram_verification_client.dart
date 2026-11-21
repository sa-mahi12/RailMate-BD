/// Telegram contact verification client (RailMate BD, P41).
///
/// This is the phone-verification *alternative* to Supabase SMS OTP: the user
/// shares their own number through Telegram, an Edge Function validates the
/// contact card, and the app reads back the verification row. It is not an SMS
/// check and never sets `phone_confirmed_at`.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Lifecycle of a challenge as stored on the server.
enum TelegramChallengeState {
  pending,
  contactShared,
  verified,
  expired,
  cancelled,
}

/// One challenge created by the `telegram-challenge` Edge Function.
class TelegramChallenge {
  final String id;
  final String deepLink;
  final DateTime expiresAt;

  const TelegramChallenge({
    required this.id,
    required this.deepLink,
    required this.expiresAt,
  });
}

/// Server-side status of a challenge, read by the client.
class TelegramChallengeStatus {
  final TelegramChallengeState state;
  final String maskedPhone;
  final String method;
  final DateTime? verifiedAt;

  const TelegramChallengeStatus({
    required this.state,
    this.maskedPhone = '',
    this.method = 'telegram_contact',
    this.verifiedAt,
  });
}

/// Why a Telegram verification call failed. The message is safe to display.
enum TelegramVerificationErrorKind {
  rateLimited,
  notConfigured,
  network,
  backend,
}

class TelegramVerificationException implements Exception {
  final TelegramVerificationErrorKind kind;
  final String message;

  const TelegramVerificationException({
    required this.kind,
    required this.message,
  });

  @override
  String toString() => 'TelegramVerificationException($kind): $message';
}

/// Client surface used by [TelegramVerificationState]; fakes in tests.
abstract class TelegramVerificationClient {
  /// True only for the in-memory fake (never in production composition).
  bool get isDemo;

  Future<TelegramChallenge> createChallenge();

  /// Null when the row no longer exists (the caller treats that as expired).
  Future<TelegramChallengeStatus?> fetchStatus(String challengeId);

  /// The account's existing verified row, if any (used to restore the profile
  /// after an app restart). Never invents a verification.
  Future<TelegramChallengeStatus?> fetchLatestVerified();

  Future<void> cancel(String challengeId);
}

/// Production client: Edge Function for creation, RLS-scoped read for status.
class SupabaseTelegramVerificationClient implements TelegramVerificationClient {
  final SupabaseClient supabase;

  const SupabaseTelegramVerificationClient({required this.supabase});

  @override
  bool get isDemo => false;

  @override
  Future<TelegramChallenge> createChallenge() async {
    final FunctionResponse response;
    try {
      response = await supabase.functions.invoke(
        'telegram-challenge',
        body: <String, Object?>{'action': 'create'},
      );
    } on FunctionException catch (e) {
      throw _fromStatus(e.status, e.details);
    } catch (_) {
      throw const TelegramVerificationException(
        kind: TelegramVerificationErrorKind.network,
        message:
            'Could not reach the verification service. Check your connection.',
      );
    }

    final Object? data = response.data;
    if (data is! Map) {
      throw const TelegramVerificationException(
        kind: TelegramVerificationErrorKind.backend,
        message: 'The verification service returned an unexpected answer.',
      );
    }
    final Object? link = data['deep_link'];
    final Object? id = data['challenge_id'];
    final Object? expires = data['expires_at'];
    if (link is! String || id is! String || link.isEmpty) {
      throw const TelegramVerificationException(
        kind: TelegramVerificationErrorKind.backend,
        message: 'The verification service returned an unexpected answer.',
      );
    }
    return TelegramChallenge(
      id: id,
      deepLink: link,
      expiresAt: expires is String
          ? DateTime.tryParse(expires) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  Future<TelegramChallengeStatus?> fetchStatus(String challengeId) async {
    try {
      final Map<String, dynamic>? row = await supabase
          .from('phone_verifications')
          .select('status, phone_masked, method, verified_at')
          .eq('id', challengeId)
          .maybeSingle();
      if (row == null) return null;
      return TelegramChallengeStatus(
        state: _stateFromString(row['status'] as String?),
        maskedPhone: (row['phone_masked'] as String?) ?? '',
        method: (row['method'] as String?) ?? 'telegram_contact',
        verifiedAt: DateTime.tryParse((row['verified_at'] as String?) ?? ''),
      );
    } on PostgrestException {
      rethrow;
    } catch (_) {
      throw const TelegramVerificationException(
        kind: TelegramVerificationErrorKind.network,
        message:
            'Could not check the verification status. Check your connection.',
      );
    }
  }

  @override
  Future<TelegramChallengeStatus?> fetchLatestVerified() async {
    try {
      final Map<String, dynamic>? row = await supabase
          .from('phone_verifications')
          .select('status, phone_masked, method, verified_at')
          .eq('status', 'verified')
          .order('verified_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return TelegramChallengeStatus(
        state: TelegramChallengeState.verified,
        maskedPhone: (row['phone_masked'] as String?) ?? '',
        method: (row['method'] as String?) ?? 'telegram_contact',
        verifiedAt: DateTime.tryParse((row['verified_at'] as String?) ?? ''),
      );
    } catch (_) {
      // A failed restore must never invent a verification.
      return null;
    }
  }

  @override
  Future<void> cancel(String challengeId) async {
    try {
      await supabase.functions.invoke(
        'telegram-challenge',
        body: <String, Object?>{'action': 'cancel'},
      );
    } on FunctionException catch (e) {
      throw _fromStatus(e.status, e.details);
    } catch (_) {
      // Cancellation is best effort: the row also expires on its own.
    }
  }

  static TelegramChallengeState _stateFromString(String? raw) {
    switch (raw) {
      case 'contact_shared':
        return TelegramChallengeState.contactShared;
      case 'verified':
        return TelegramChallengeState.verified;
      case 'expired':
        return TelegramChallengeState.expired;
      case 'cancelled':
        return TelegramChallengeState.cancelled;
      default:
        return TelegramChallengeState.pending;
    }
  }

  static TelegramVerificationException _fromStatus(
    int status,
    Object? details,
  ) {
    switch (status) {
      case 429:
        return const TelegramVerificationException(
          kind: TelegramVerificationErrorKind.rateLimited,
          message: 'Too many attempts. Wait a few minutes and try again.',
        );
      case 503:
        return const TelegramVerificationException(
          kind: TelegramVerificationErrorKind.notConfigured,
          message:
              'Telegram verification is not available yet. Use email '
              'verification for now.',
        );
      case 401:
        return const TelegramVerificationException(
          kind: TelegramVerificationErrorKind.backend,
          message: 'Sign in again to verify your phone number.',
        );
      default:
        return const TelegramVerificationException(
          kind: TelegramVerificationErrorKind.backend,
          message: 'The verification service could not start a challenge.',
        );
    }
  }
}

/// In-memory client for the test composition. It never verifies anything, so
/// widget tests cannot accidentally assert a successful phone verification.
class DemoTelegramVerificationClient implements TelegramVerificationClient {
  @override
  bool get isDemo => true;

  @override
  Future<TelegramChallenge> createChallenge() async {
    return TelegramChallenge(
      id: 'demo-challenge',
      deepLink: 'https://t.me/railmate_demo_bot?start=demo',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<TelegramChallengeStatus?> fetchStatus(String challengeId) async {
    return const TelegramChallengeStatus(state: TelegramChallengeState.pending);
  }

  @override
  Future<TelegramChallengeStatus?> fetchLatestVerified() async => null;

  @override
  Future<void> cancel(String challengeId) async {}
}
