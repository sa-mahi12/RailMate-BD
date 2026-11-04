import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:railmate_bd/features/auth/supabase_auth_client.dart';

void main() {
  test(
    'verification requires a session, not only a confirmed user response',
    () async {
      final client = SupabaseClient(
        'https://example.com',
        'test-publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'id': 'otp-user',
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-11-04T00:00:00Z',
              'email': 'otp@example.com',
              'email_confirmed_at': '2026-11-04T00:00:00Z',
            }),
            200,
          ),
        ),
      );
      addTearDown(client.dispose);
      final user = await SupabaseAuthClient(supabase: client)
          .verifyEmailOtp(email: 'otp@example.com', token: '123456');
      expect(user, isNull);
    },
  );

  test(
    'email signup verification sends email OTP type through installed SDK',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.com',
        'test-publishable',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"code":"otp_expired","msg":"Token has expired"}',
            403,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseAuthClient(supabase: client)
            .verifyEmailOtp(email: 'otp@example.com', token: '123456'),
        throwsA(isA<AuthException>()),
      );
      expect(requests.single.url.path, '/auth/v1/verify');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['type'], 'email');
      expect(body['email'], 'otp@example.com');
      expect(body['token'], '123456');
    },
  );

  test(
    'resend still requests a signup code rather than passwordless login',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.com',
        'test-publishable',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await SupabaseAuthClient(supabase: client)
          .resendConfirmation('otp@example.com');
      expect(requests.single.url.path, '/auth/v1/resend');
      expect(jsonDecode(requests.single.body)['type'], 'signup');
    },
  );
}
