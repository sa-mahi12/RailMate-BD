import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/phone/phone_auth_repository.dart';
import 'package:railmate_bd/features/auth/phone/phone_state.dart';

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
