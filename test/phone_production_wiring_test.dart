import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/app/dependencies.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';
import 'package:railmate_bd/features/auth/phone/phone_auth_repository.dart';
import 'package:railmate_bd/features/auth/phone/phone_state.dart';
import 'package:railmate_bd/features/auth/phone/phone_verify_screen.dart';
import 'package:railmate_bd/features/auth/verify_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

import 'home/home_test_fakes.dart';

/// Production phone-OTP wiring (teacher final gate, 2026-11-03).
///
/// The teacher item is "email and phone verification" — so the phone action
/// must reach a REAL server-backed OTP UI, and no fixed token or demo banner
/// may appear in the production composition. These tests pin the wiring
/// (adapter class, demo flag, navigation, copy). They deliberately do NOT claim
/// live SMS delivery: that needs an SMS provider on the hosted project and a
/// real handset, and is tracked as an owner-side gate.
void main() {
  PhoneState realPhoneState() {
    // No network is touched at construction time; this only builds the real
    // adapter over an offline client so identity can be asserted.
    final SupabaseClient client = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      // No background token timer: this client only identifies the adapter.
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return PhoneState(
      repository: PhoneAuthRepository(
        client: SupabasePhoneOtpClient(supabase: client),
      ),
    );
  }

  group('composition', () {
    test('production adapter is the Supabase client, not the fake', () {
      final PhoneState state = realPhoneState();
      expect(state.repository.client, isA<SupabasePhoneOtpClient>());
      expect(state.isDemo, isFalse);
    });

    test('test composition is explicitly the demo fake', () async {
      final AuthState auth = await signedOutAuth();
      final AppDependencies deps = AppDependencies.test(
        auth: auth,
        searchApi: FakeSearchApi(),
      );
      expect(deps.phoneState.isDemo, isTrue);
    });
  });

  group('Verify screen phone action', () {
    Future<void> pumpVerify(WidgetTester tester, PhoneState phones) async {
      final AuthState auth = await signedOutAuth();
      await tester.pumpWidget(
        MaterialApp(
          home: VerifyScreen(
            auth: auth,
            email: 'traveller@example.com',
            phoneState: phones,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verify with Phone Number'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the OTP screen instead of a placeholder dialog', (
      WidgetTester tester,
    ) async {
      await pumpVerify(tester, realPhoneState());

      await tester.tap(find.text('Verify with Phone Number'));
      await tester.pumpAndSettle();

      expect(find.byType(PhoneVerifyScreen), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Phone Number'), findsWidgets);
      expect(find.text('Send Code'), findsOneWidget);
    });

    testWidgets('production OTP copy never claims demo or a fixed code', (
      WidgetTester tester,
    ) async {
      await pumpVerify(tester, realPhoneState());

      await tester.tap(find.text('Verify with Phone Number'));
      await tester.pumpAndSettle();

      expect(find.textContaining('DEMO'), findsNothing);
      expect(find.textContaining('123456'), findsNothing);
      expect(find.textContaining('no real code'), findsNothing);
      expect(
        find.textContaining('Standard SMS rates may apply'),
        findsOneWidget,
      );
    });

    testWidgets('the demo fake still shows an honest demo notice', (
      WidgetTester tester,
    ) async {
      await pumpVerify(tester, realPhoneState());

      // Directly push the demo-backed state to prove the notice is gated on
      // the fake, not on a build flag that could leak into production.
      await tester.pumpWidget(
        MaterialApp(
          home: PhoneVerifyScreen(
            phones: PhoneState(
              repository: PhoneAuthRepository(client: FakePhoneOtpClient()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('DEMO ONLY'), findsOneWidget);
    });
  });
}
