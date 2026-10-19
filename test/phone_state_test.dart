import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/phone/phone_auth_repository.dart';
import 'package:railmate_bd/features/auth/phone/phone_state.dart';

/// Throws raw backend text (never a [PhoneAuthException]) to prove the
/// consumer gate strips it before it reaches the UI.
class _RawThrowingOtpClient implements PhoneOtpClient {
  @override
  Future<void> requestOtp(String phone) async {
    throw Exception('PostgrestException: connection refused (raw)');
  }

  @override
  Future<AuthUser> verifyOtp({
    required String phone,
    required String token,
  }) async {
    throw Exception('SocketException: OS Error (raw)');
  }
}

void main() {
  test('cooldown blocks immediate resend without backend call', () async {
    DateTime now = DateTime(2026, 9, 27);
    final FakePhoneOtpClient fake = FakePhoneOtpClient();
    final PhoneState state = PhoneState(
      repository: PhoneAuthRepository(client: fake),
      clock: () => now,
    );
    await state.requestCode('+8801712345678');
    expect(state.status, PhoneStatus.codeSent);
    await state.resend();
    expect(state.status, PhoneStatus.error);
    expect(state.rateLimited, isTrue);
    expect(fake.requests, 1);
    now = now.add(const Duration(seconds: 31));
    await state.resend();
    expect(state.status, PhoneStatus.codeSent);
    expect(fake.requests, 2);
  });

  test('raw send failure surfaces clean copy without backend text', () async {
    final PhoneState state = PhoneState(
      repository: PhoneAuthRepository(client: _RawThrowingOtpClient()),
    );
    await state.requestCode('+8801712345678');
    expect(state.status, PhoneStatus.error);
    expect(
      state.errorMessage,
      'Could not send the code. Check your connection and try again.',
    );
    expect(state.errorMessage, isNot(contains('PostgrestException')));
  });

  test(
    'raw verify failure maps to PhoneAuthException without raw text',
    () async {
      final PhoneAuthRepository repo = PhoneAuthRepository(
        client: _RawThrowingOtpClient(),
      );
      try {
        await repo.verifyOtp(rawPhone: '+8801712345678', token: '123456');
        fail('expected PhoneAuthException');
      } on PhoneAuthException catch (e) {
        expect(e.message, "That code didn't work. Check it and try again.");
        expect(e.message, isNot(contains('SocketException')));
      }
    },
  );

  test('correct demo code verifies', () async {
    final PhoneState state = PhoneState(
      repository: PhoneAuthRepository(client: FakePhoneOtpClient()),
    );
    await state.requestCode('01712345678');
    await state.verifyCode('123456');
    expect(state.isPhoneVerified, isTrue);
    expect(state.user?.phone, '+8801712345678');
  });
}
