import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_client.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_state.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verify_section.dart';

import 'support/telegram_fakes.dart';

Future<void> pumpSection(
  WidgetTester tester,
  TelegramVerificationState state,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TelegramVerifySection(state: state)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('TelegramVerifySection', () {
    testWidgets('idle offers the Telegram button and no verified claim', (
      WidgetTester tester,
    ) async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(),
        openLink: (String url) async {},
      );
      await pumpSection(tester, state);

      expect(find.text('Verify with Telegram'), findsOneWidget);
      expect(find.textContaining('Phone verified'), findsNothing);
      state.dispose();
    });

    testWidgets('waiting shows how to finish in Telegram and a cancel action', (
      WidgetTester tester,
    ) async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(),
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );
      await pumpSection(tester, state);
      await state.start();
      await tester.pump();

      expect(find.textContaining('Waiting for Telegram'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('Phone verified'), findsNothing);
      state.dispose();
    });

    testWidgets('verified shows the masked number and the method', (
      WidgetTester tester,
    ) async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(
          statusOverride: const TelegramChallengeStatus(
            state: TelegramChallengeState.verified,
            maskedPhone: '+880*****5678',
          ),
        ),
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );
      await pumpSection(tester, state);
      await state.start();
      await state.pollOnce();
      await tester.pump();

      expect(find.textContaining('Phone verified'), findsOneWidget);
      expect(find.textContaining('+880*****5678'), findsOneWidget);
      expect(find.text('Verify with Telegram'), findsNothing);
      state.dispose();
    });

    testWidgets('an existing verification survives re-entry', (
      WidgetTester tester,
    ) async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(
          latestVerified: const TelegramChallengeStatus(
            state: TelegramChallengeState.verified,
            maskedPhone: '+880*****5678',
          ),
        ),
        openLink: (String url) async {},
      );
      await pumpSection(tester, state);
      await tester.pumpAndSettle();

      expect(find.textContaining('Phone verified'), findsOneWidget);
      expect(find.textContaining('+880*****5678'), findsOneWidget);
      expect(find.text('Verify with Telegram'), findsNothing);
      state.dispose();
    });

    testWidgets('an error is shown with a retry action', (
      WidgetTester tester,
    ) async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(
          createError: const TelegramVerificationException(
            kind: TelegramVerificationErrorKind.backend,
            message: 'Challenge could not be created.',
          ),
        ),
        openLink: (String url) async {},
      );
      await pumpSection(tester, state);
      await state.start();
      await tester.pump();

      expect(find.textContaining('could not be created'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      state.dispose();
    });

    testWidgets('an expired challenge offers a fresh start', (
      WidgetTester tester,
    ) async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(
          statusOverride: const TelegramChallengeStatus(
            state: TelegramChallengeState.expired,
          ),
        ),
        openLink: (String url) async {},
        pollInterval: const Duration(hours: 1),
      );
      await pumpSection(tester, state);
      await state.start();
      await state.pollOnce();
      await tester.pump();

      expect(find.textContaining('expired'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('Phone verified'), findsNothing);
      state.dispose();
    });
  });
}
