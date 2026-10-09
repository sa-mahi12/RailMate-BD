import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/forgot_password_screen.dart';
import 'package:railmate_bd/features/auth/password_recovery.dart';

import '../auth_repository_test.dart' show FakeAuthClient;

/// Deep-link contract for `railmatebd://auth/reset-password`. Pure Dart —
/// no Flutter binding, no network.
void main() {
  AuthState fakeAuth() {
    final auth = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    addTearDown(() {
      auth.unsubFromAuth();
      auth.dispose();
    });
    return auth;
  }

  group('ForgotPasswordScreen recovery mode', () {
    testWidgets('email mode asks for the account email', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(auth: fakeAuth())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account email'), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);
      expect(find.text('Set new password'), findsNothing);
    });

    testWidgets('link arrival opens directly on the new-password pane', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(auth: fakeAuth(), startInRecovery: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account email'), findsNothing);
      expect(find.text('Send reset link'), findsNothing);
      expect(
        find.textContaining('arrived from your reset link'),
        findsOneWidget,
      );
      expect(find.text('Set new password'), findsOneWidget);
    });
  });

  Uri link(String raw) => Uri.parse(raw);

  group('isPasswordRecoveryLink', () {
    test('accepts the real Supabase fragment form', () {
      expect(
        isPasswordRecoveryLink(
          link(
            'railmatebd://auth/reset-password#access_token=aaa&refresh_token=rrr&type=recovery',
          ),
        ),
        isTrue,
      );
    });

    test('accepts the query-parameter form', () {
      expect(
        isPasswordRecoveryLink(
          link(
            'railmatebd://auth/reset-password?access_token=aaa&refresh_token=rrr&type=recovery',
          ),
        ),
        isTrue,
      );
    });

    test('rejects wrong scheme, host, path and type', () {
      expect(
        isPasswordRecoveryLink(
          link(
            'https://auth/reset-password#access_token=a&refresh_token=r&type=recovery',
          ),
        ),
        isFalse,
      );
      expect(
        isPasswordRecoveryLink(
          link(
            'railmatebd://other/reset-password#access_token=a&refresh_token=r&type=recovery',
          ),
        ),
        isFalse,
      );
      expect(
        isPasswordRecoveryLink(
          link(
            'railmatebd://auth/login#access_token=a&refresh_token=r&type=recovery',
          ),
        ),
        isFalse,
      );
      expect(
        isPasswordRecoveryLink(
          link(
            'railmatebd://auth/reset-password#access_token=a&refresh_token=r&type=signup',
          ),
        ),
        isFalse,
      );
      expect(
        isPasswordRecoveryLink(link('railmatebd://auth/reset-password')),
        isFalse,
      );
    });
  });

  group('parseRecoveryLink', () {
    test('extracts both tokens from the fragment', () {
      final creds = parseRecoveryLink(
        link(
          'railmatebd://auth/reset-password#access_token=AAA&refresh_token=RRR&type=recovery&expires_in=3600',
        ),
      )!;
      expect(creds.accessToken, 'AAA');
      expect(creds.refreshToken, 'RRR');
    });

    test('extracts both tokens from the query', () {
      final creds = parseRecoveryLink(
        link(
          'railmatebd://auth/reset-password?access_token=AAA&refresh_token=RRR&type=recovery',
        ),
      )!;
      expect(creds.accessToken, 'AAA');
      expect(creds.refreshToken, 'RRR');
    });

    test('returns null when a token is missing', () {
      expect(
        parseRecoveryLink(
          link(
            'railmatebd://auth/reset-password#access_token=AAA&type=recovery',
          ),
        ),
        isNull,
      );
      expect(
        parseRecoveryLink(
          link(
            'railmatebd://auth/reset-password#refresh_token=RRR&type=recovery',
          ),
        ),
        isNull,
      );
    });

    test('returns null for non-recovery links, never throws', () {
      expect(parseRecoveryLink(link('railmatebd://auth/login')), isNull);
      expect(
        parseRecoveryLink(link('https://example.com/#weird fragment here')),
        isNull,
      );
    });
  });
}
