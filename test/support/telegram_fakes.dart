import 'package:railmate_bd/features/auth/telegram/telegram_verification_client.dart';

/// Fake client for the Telegram verification lane. Never talks to Telegram or
/// Supabase; each test sets exactly the response it wants to reason about.
class FakeTelegramClient implements TelegramVerificationClient {
  FakeTelegramClient({
    this.createError,
    this.statusAfterCreate = TelegramChallengeState.pending,
    this.statusOverride,
    this.cancelError,
    this.fetchError,
    this.returnNullStatus = false,
    this.latestVerified,
  });

  TelegramVerificationException? createError;
  Object? cancelError;
  Object? fetchError;
  bool returnNullStatus;
  TelegramChallengeStatus? latestVerified;
  TelegramChallengeState statusAfterCreate;
  TelegramChallengeStatus? statusOverride;
  Future<TelegramChallenge> Function()? createResponse;
  Future<TelegramChallengeStatus?> Function(String id)? statusResponse;
  Future<TelegramChallengeStatus?> Function()? restoreResponse;
  Future<void> Function(String id)? cancelResponse;

  int createCalls = 0;
  int fetchCalls = 0;
  int cancelCalls = 0;
  String? cancelledId;

  @override
  bool get isDemo => true;

  @override
  Future<TelegramChallenge> createChallenge() async {
    createCalls++;
    if (createResponse != null) return createResponse!();
    final TelegramVerificationException? error = createError;
    if (error != null) throw error;
    return TelegramChallenge(
      id: 'challenge-$createCalls',
      deepLink: 'https://t.me/railmate_test_bot?start=token$createCalls',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<TelegramChallengeStatus?> fetchStatus(String challengeId) async {
    fetchCalls++;
    if (statusResponse != null) return statusResponse!(challengeId);
    final Object? error = fetchError;
    if (error != null) throw error;
    if (returnNullStatus) return null;
    if (statusOverride != null) return statusOverride;
    if (statusAfterCreate == TelegramChallengeState.verified) {
      return const TelegramChallengeStatus(
        state: TelegramChallengeState.verified,
        maskedPhone: '+880*****5678',
        method: 'telegram_contact',
      );
    }
    return TelegramChallengeStatus(state: statusAfterCreate);
  }

  @override
  Future<TelegramChallengeStatus?> fetchLatestVerified() async =>
      restoreResponse == null ? latestVerified : await restoreResponse!();

  @override
  Future<void> cancel(String challengeId) async {
    cancelCalls++;
    cancelledId = challengeId;
    if (cancelResponse != null) return cancelResponse!(challengeId);
    final Object? error = cancelError;
    if (error != null) throw error;
  }
}
