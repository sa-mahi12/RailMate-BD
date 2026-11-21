import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_client.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_state.dart';

import 'support/telegram_fakes.dart';

void main() {
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

    test('a failed restore never invents a verification', () async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(fetchError: StateError('offline')),
        openLink: (String url) async {},
      );

      await state.restore();

      expect(state.isVerified, isFalse);
      expect(state.maskedPhone, isEmpty);
      state.dispose();
    });

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
