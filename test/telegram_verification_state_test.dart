import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_client.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_state.dart';

import 'support/telegram_fakes.dart';

void main() {
  group('Telegram async lifecycle', () {
    const TelegramChallengeStatus verified = TelegramChallengeStatus(
      state: TelegramChallengeState.verified,
      maskedPhone: '+880*****5678',
    );
    TelegramVerificationState makeState(FakeTelegramClient client) {
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (_) async {},
        pollInterval: const Duration(hours: 1),
      );
      addTearDown(state.dispose);
      return state;
    }

    test(
      'late poll cannot undo cancel even while backend cancellation waits',
      () async {
        final Completer<TelegramChallengeStatus?> response =
            Completer<TelegramChallengeStatus?>();
        final Completer<void> cancellation = Completer<void>();
        final FakeTelegramClient client = FakeTelegramClient();
        client.statusResponse = (_) => response.future;
        client.cancelResponse = (_) => cancellation.future;
        final TelegramVerificationState state = makeState(client);
        await state.start();
        final Future<void> polling = state.pollOnce();
        final Future<void> cancelling = state.cancel();
        response.complete(verified);
        await polling;
        final TelegramStatus afterPoll = state.status;
        cancellation.complete();
        await cancelling;
        expect(afterPoll, TelegramStatus.cancelled);
        expect(state.isVerified, isFalse);
        expect(state.maskedPhone, isEmpty);
      },
    );

    test(
      'a reset invalidates pending hydration and permits a new restore',
      () async {
        final Completer<TelegramChallengeStatus?> response =
            Completer<TelegramChallengeStatus?>();
        final FakeTelegramClient client = FakeTelegramClient()
          ..restoreResponse = () => response.future;
        final TelegramVerificationState state = makeState(client);
        final Future<void> restoring = state.restore();
        state.reset();
        response.complete(verified);
        await restoring;
        expect(state.isVerified, isFalse);
        client.restoreResponse = null;
        client.latestVerified = verified;
        await state.restore();
        expect(state.isVerified, isTrue);
      },
    );

    test('late challenge creation after cancel never opens Telegram', () async {
      final Completer<TelegramChallenge> response =
          Completer<TelegramChallenge>();
      final FakeTelegramClient client = FakeTelegramClient()
        ..createResponse = () => response.future;
      final List<String> opened = <String>[];
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (url) async => opened.add(url),
        pollInterval: const Duration(hours: 1),
      );
      addTearDown(state.dispose);
      final Future<void> starting = state.start();
      await state.cancel();
      response.complete(
        TelegramChallenge(
          id: 'old',
          deepLink: 'https://t.me/test?start=old',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      await starting;
      expect(opened, isEmpty);
      expect(state.status, TelegramStatus.cancelled);
    });

    test(
      'late poll for an old challenge cannot verify a new challenge',
      () async {
        final Completer<TelegramChallengeStatus?> response =
            Completer<TelegramChallengeStatus?>();
        final FakeTelegramClient client = FakeTelegramClient()
          ..statusResponse = (_) => response.future;
        final TelegramVerificationState state = makeState(client);
        await state.start();
        final Future<void> polling = state.pollOnce();
        await state.start();
        response.complete(verified);
        await polling;
        expect(state.status, TelegramStatus.waiting);
        expect(state.maskedPhone, isEmpty);
      },
    );

    test('slow status fetches never overlap for one challenge', () async {
      final Completer<TelegramChallengeStatus?> response =
          Completer<TelegramChallengeStatus?>();
      final FakeTelegramClient client = FakeTelegramClient()
        ..statusResponse = (_) => response.future;
      final TelegramVerificationState state = makeState(client);
      await state.start();
      final Future<void> first = state.pollOnce();
      final Future<void> second = state.pollOnce();
      final int requestsWhilePending = client.fetchCalls;
      response.complete(verified);
      await Future.wait(<Future<void>>[first, second]);
      expect(requestsWhilePending, 1);
      expect(state.isVerified, isTrue);
    });

    test(
      'disposing invalidates a pending poll without notifier errors',
      () async {
        final Completer<TelegramChallengeStatus?> response =
            Completer<TelegramChallengeStatus?>();
        final FakeTelegramClient client = FakeTelegramClient()
          ..statusResponse = (_) => response.future;
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (_) async {},
          pollInterval: const Duration(hours: 1),
        );
        await state.start();
        final Future<void> polling = state.pollOnce();
        state.dispose();
        response.complete(verified);
        await expectLater(polling, completes);
      },
    );
  });
  group('TelegramVerificationState', () {
    test(
      'start opens the deep link and waits without claiming success',
      () async {
        final FakeTelegramClient client = FakeTelegramClient();
        final List<String> opened = <String>[];
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (String url) async => opened.add(url),
        );

        await state.start();

        expect(state.status, TelegramStatus.waiting);
        expect(state.isVerified, isFalse);
        expect(opened, hasLength(1));
        expect(opened.single, contains('start=token1'));
        expect(client.createCalls, 1);
        state.dispose();
      },
    );

    test(
      'a verified backend row is the only thing that sets verified',
      () async {
        final FakeTelegramClient client = FakeTelegramClient(
          statusAfterCreate: TelegramChallengeState.verified,
        );
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (String url) async {},
          pollInterval: const Duration(hours: 1),
        );

        await state.start();
        expect(state.isVerified, isFalse, reason: 'no confirmation yet');

        await state.pollOnce();
        expect(state.status, TelegramStatus.verified);
        expect(state.isVerified, isTrue);
        expect(state.maskedPhone, '+880*****5678');
        expect(state.method, 'telegram_contact');
        state.dispose();
      },
    );

    test('an expired challenge tells the user to start again', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        statusOverride: const TelegramChallengeStatus(
          state: TelegramChallengeState.expired,
        ),
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );

      await state.start();
      await state.pollOnce();

      expect(state.status, TelegramStatus.expired);
      expect(state.isVerified, isFalse);
      expect(state.canRetry, isTrue);
      state.dispose();
    });

    test('a missing backend row is treated as expired, not verified', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        returnNullStatus: true,
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );

      await state.start();
      await state.pollOnce();

      expect(state.status, TelegramStatus.expired);
      expect(state.isVerified, isFalse);
      state.dispose();
    });

    test('cancel calls the backend and clears the pending state', () async {
      final FakeTelegramClient client = FakeTelegramClient();
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );

      await state.start();
      await state.cancel();

      expect(state.status, TelegramStatus.cancelled);
      expect(client.cancelCalls, 1);
      expect(client.cancelledId, 'challenge-1');
      expect(state.isVerified, isFalse);
      state.dispose();
    });

    test(
      'a backend failure surfaces an honest error and no verification',
      () async {
        final FakeTelegramClient client = FakeTelegramClient(
          createError: const TelegramVerificationException(
            kind: TelegramVerificationErrorKind.backend,
            message: 'Challenge could not be created.',
          ),
        );
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (String url) async {},
        );

        await state.start();

        expect(state.status, TelegramStatus.error);
        expect(state.errorMessage, contains('could not be created'));
        expect(state.isVerified, isFalse);
        state.dispose();
      },
    );

    test('rate limiting is reported as a wait, not as success', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        createError: const TelegramVerificationException(
          kind: TelegramVerificationErrorKind.rateLimited,
          message: 'Too many attempts. Wait a few minutes and try again.',
        ),
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
      );

      await state.start();

      expect(state.status, TelegramStatus.error);
      expect(state.errorMessage.toLowerCase(), contains('wait'));
      expect(state.isVerified, isFalse);
      state.dispose();
    });

    test(
      'an unconfigured bot is explained without pretending to work',
      () async {
        final FakeTelegramClient client = FakeTelegramClient(
          createError: const TelegramVerificationException(
            kind: TelegramVerificationErrorKind.notConfigured,
            message: 'Telegram verification is not available yet.',
          ),
        );
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (String url) async {},
        );

        await state.start();

        expect(state.status, TelegramStatus.error);
        expect(state.errorMessage, contains('not available'));
        expect(state.isVerified, isFalse);
        state.dispose();
      },
    );

    test('retry after expiry creates a fresh challenge', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        statusOverride: const TelegramChallengeStatus(
          state: TelegramChallengeState.expired,
        ),
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );

      await state.start();
      await state.pollOnce();
      expect(state.status, TelegramStatus.expired);

      client.statusOverride = const TelegramChallengeStatus(
        state: TelegramChallengeState.verified,
        maskedPhone: '+880*****5678',
      );
      await state.start();
      expect(client.createCalls, 2);
      expect(state.status, TelegramStatus.waiting);

      await state.pollOnce();
      expect(state.status, TelegramStatus.verified);
      state.dispose();
    });

    test(
      'a cancelled challenge reported by the backend stops waiting',
      () async {
        final FakeTelegramClient client = FakeTelegramClient(
          statusOverride: const TelegramChallengeStatus(
            state: TelegramChallengeState.cancelled,
          ),
        );
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (String url) async {},
          pollInterval: const Duration(hours: 1),
        );

        await state.start();
        await state.pollOnce();

        expect(state.status, TelegramStatus.cancelled);
        state.dispose();
      },
    );

    test('an existing verification is restored after an app restart', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        latestVerified: const TelegramChallengeStatus(
          state: TelegramChallengeState.verified,
          maskedPhone: '+880*****5678',
        ),
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
      );

      await state.restore();

      expect(state.status, TelegramStatus.verified);
      expect(state.isVerified, isTrue);
      expect(state.maskedPhone, '+880*****5678');
      expect(
        client.createCalls,
        0,
        reason: 'restore never creates a challenge',
      );
      state.dispose();
    });

    test('no stored verification leaves the account unverified', () async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(),
        openLink: (String url) async {},
      );

      await state.restore();

      expect(state.status, TelegramStatus.idle);
      expect(state.isVerified, isFalse);
      state.dispose();
    });

    test(
      'a failed restore stays unverified and permits a successful retry',
      () async {
        final FakeTelegramClient client = FakeTelegramClient();
        client.restoreResponse = () async => throw StateError('offline');
        final TelegramVerificationState state = TelegramVerificationState(
          client: client,
          openLink: (String url) async {},
        );

        await state.restore();

        expect(state.isVerified, isFalse);
        expect(state.maskedPhone, isEmpty);
        client.restoreResponse = null;
        client.latestVerified = const TelegramChallengeStatus(
          state: TelegramChallengeState.verified,
          maskedPhone: '+880*****5678',
        );
        await state.restore();
        expect(state.isVerified, isTrue);
        state.dispose();
      },
    );

    test('a polling failure does not fabricate verification', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        fetchError: StateError('network down'),
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );

      await state.start();
      await state.pollOnce();

      // A transient network failure must not claim anything and must not
      // cancel a challenge that is still within its five-minute window.
      expect(state.isVerified, isFalse);
      expect(state.status, TelegramStatus.waiting);
      expect(state.maskedPhone, isEmpty);
      state.dispose();
    });

    test('a polling failure past the deadline reports a timeout', () async {
      final FakeTelegramClient client = FakeTelegramClient(
        fetchError: StateError('network down'),
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
        clock: () => DateTime.now().add(const Duration(minutes: 10)),
      );

      await state.start();
      await state.pollOnce();

      expect(state.status, TelegramStatus.error);
      expect(state.errorMessage.toLowerCase(), contains('timed out'));
      expect(state.isVerified, isFalse);
      state.dispose();
    });
  });
}
