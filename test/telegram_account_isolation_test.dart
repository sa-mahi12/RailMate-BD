import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_client.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_state.dart';

import 'home/home_test_fakes.dart';
import 'support/telegram_fakes.dart';

const AuthUser accountA = AuthUser(
  id: 'account-a',
  email: 'a@example.invalid',
  emailConfirmed: true,
);
const AuthUser accountB = AuthUser(
  id: 'account-b',
  email: 'b@example.invalid',
  emailConfirmed: true,
);
const TelegramChallengeStatus verifiedA = TelegramChallengeStatus(
  state: TelegramChallengeState.verified,
  maskedPhone: '+880*****1111',
);
const TelegramChallengeStatus verifiedB = TelegramChallengeStatus(
  state: TelegramChallengeState.verified,
  maskedPhone: '+880*****2222',
);

void main() {
  test(
    'shared dependencies clear A verification on logout and restore B',
    () async {
      final FakeAuthClient authClient = FakeAuthClient(user: accountA);
      final AuthState auth = AuthState(
        repository: AuthRepository(client: authClient),
      );
      await auth.restore();
      final FakeTelegramClient client = FakeTelegramClient(
        latestVerified: verifiedA,
      );
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (_) async {},
      );
      AppDependencies.test(
        auth: auth,
        searchApi: FakeSearchApi(),
        telegramVerification: state,
      );
      addTearDown(state.dispose);
      addTearDown(auth.dispose);
      await state.restore();
      expect(state.maskedPhone, verifiedA.maskedPhone);
      await auth.signOut();
      expect(state.isVerified, isFalse);
      expect(state.maskedPhone, isEmpty);
      authClient.user = accountB;
      await auth.signIn(email: accountB.email, password: 'test-password');
      client.latestVerified = verifiedB;
      await state.restore();
      expect(state.maskedPhone, verifiedB.maskedPhone);
    },
  );

  test(
    'A hydration cannot overwrite B after a direct account switch',
    () async {
      final FakeAuthClient authClient = FakeAuthClient(user: accountA);
      final AuthState auth = AuthState(
        repository: AuthRepository(client: authClient),
      );
      await auth.restore();
      final Completer<TelegramChallengeStatus?> oldResponse =
          Completer<TelegramChallengeStatus?>();
      final FakeTelegramClient client = FakeTelegramClient()
        ..restoreResponse = () => oldResponse.future;
      final TelegramVerificationState state = TelegramVerificationState(
        client: client,
        openLink: (_) async {},
      );
      AppDependencies.test(
        auth: auth,
        searchApi: FakeSearchApi(),
        telegramVerification: state,
      );
      addTearDown(state.dispose);
      addTearDown(auth.dispose);
      final Future<void> restoringA = state.restore();
      authClient.user = accountB;
      await auth.refreshVerification();
      client.restoreResponse = null;
      client.latestVerified = verifiedB;
      await state.restore();
      oldResponse.complete(verifiedA);
      await restoringA;
      expect(state.maskedPhone, verifiedB.maskedPhone);
    },
  );
}
