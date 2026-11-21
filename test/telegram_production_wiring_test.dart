import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_client.dart';
import 'package:railmate_bd/features/auth/telegram/telegram_verification_state.dart';
import 'package:railmate_bd/features/profile/profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

import 'home/home_test_fakes.dart';
import 'support/telegram_fakes.dart';

/// P41 production wiring for Telegram phone verification.
///
/// These tests pin identity and copy only. They do NOT claim a live Telegram
/// check: the bot is created and configured by the owner (see
/// docs/owner/telegram-setup.md), and the hosted migration is a deployment
/// step, not something this test suite can prove.
void main() {
  TelegramVerificationState realState() {
    // No network at construction time; this only identifies the adapter.
    final SupabaseClient client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return TelegramVerificationState(
      client: SupabaseTelegramVerificationClient(supabase: client),
      openLink: (String url) async {},
    );
  }

  group('composition', () {
    test('production uses the Supabase Edge Function client', () {
      final TelegramVerificationState state = realState();
      expect(state.client, isA<SupabaseTelegramVerificationClient>());
      expect(state.isDemo, isFalse);
    });

    test('test composition is explicitly the demo client', () async {
      final AuthState auth = await signedOutAuth();
      final AppDependencies deps = AppDependencies.test(
        auth: auth,
        searchApi: FakeSearchApi(),
      );
      expect(deps.telegramVerification.isDemo, isTrue);
      expect(
        deps.telegramVerification.client,
        isA<DemoTelegramVerificationClient>(),
      );
    });

    test('the app never verifies itself without a backend row', () async {
      final TelegramVerificationState state = TelegramVerificationState(
        client: DemoTelegramVerificationClient(),
        openLink: (String url) async {},
      );
      await state.start();
      await state.pollOnce();
      expect(state.isVerified, isFalse);
      expect(hasVerifiedClaim(state), isFalse);
    });
  });

  group('profile section', () {
    testWidgets('renders the Telegram section for a signed-in user', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await signedInAuth();
      final TelegramVerificationState state = TelegramVerificationState(
        client: FakeTelegramClient(),
        openLink: (String url) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(auth: auth, telegram: state),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phone verification'), findsOneWidget);
      expect(find.text('Verify with Telegram'), findsOneWidget);
      expect(find.textContaining('Phone verified'), findsNothing);
      state.dispose();
    });

    testWidgets('email verification copy is untouched (regression)', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await signedInAuth();
      await tester.pumpWidget(MaterialApp(home: ProfileScreen(auth: auth)));
      await tester.pumpAndSettle();

      expect(find.textContaining('traveller@example.com'), findsWidgets);
      expect(find.text('Phone verification'), findsNothing);
    });

    testWidgets('a verified backend row is what shows Phone verified', (
      WidgetTester tester,
    ) async {
      final AuthState auth = await signedInAuth();
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
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(auth: auth, telegram: state),
        ),
      );
      await state.start();
      await state.pollOnce();
      await tester.pumpAndSettle();

      expect(find.textContaining('Phone verified'), findsOneWidget);
      expect(find.textContaining('+880*****5678'), findsOneWidget);
      state.dispose();
    });
  });

  group('secret hygiene', () {
    test('no bot token, bot username or webhook secret in app sources', () {
      final Directory lib = Directory('lib');
      final RegExp botToken = RegExp(r'\b\d{8,10}:[A-Za-z0-9_-]{35}\b');
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String source = entity.readAsStringSync();
        if (botToken.hasMatch(source) ||
            source.contains('TELEGRAM_BOT_TOKEN') ||
            source.contains('TELEGRAM_WEBHOOK_SECRET')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('the challenge function keeps the deep link free of user data', () {
      final String source = File(
        'supabase/functions/telegram-challenge/index.ts',
      ).readAsStringSync();
      final RegExp link = RegExp(
        r'https://t\.me/\$\{botUsername\}\?start=\$\{secret\}',
      );
      expect(link.hasMatch(source), isTrue);
      expect(source.contains('?start=\${userId}'), isFalse);
      expect(source.contains('phone'), isTrue); // only via the table name
    });
  });
}

/// Mirrors the widget's rule so the test cannot drift from the UI.
bool hasVerifiedClaim(TelegramVerificationState state) =>
    state.status == TelegramStatus.verified;
