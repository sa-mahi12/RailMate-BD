import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/phone/phone_auth_repository.dart';

void main() {
  test('rejects non-BD numbers without touching the client', () async {
    final FakePhoneOtpClient fake = FakePhoneOtpClient();
    final PhoneAuthRepository repo = PhoneAuthRepository(client: fake);
    expect(
      () => repo.requestOtp('017123'),
      throwsA(
        isA<PhoneAuthException>().having(
          (PhoneAuthException e) => e.kind,
          'kind',
          PhoneAuthErrorKind.invalidPhone,
        ),
      ),
    );
    expect(fake.requests, 0);
  });

  test('normalises local 01XXXXXXXXX to E.164', () {
    expect(
      PhoneAuthRepository.normalizePhone('01712 345678'),
      '+8801712345678',
    );
    expect(PhoneAuthRepository.isValidPhone('+8801712345678'), isTrue);
  });

  test('maps server 429 to rateLimited', () async {
    final PhoneAuthRepository repo = PhoneAuthRepository(
      client: FakePhoneOtpClient(failRateLimitAfter: 0),
    );
    try {
      await repo.requestOtp('+8801712345678');
      fail('expected PhoneAuthException');
    } on PhoneAuthException catch (e) {
      expect(e.kind, PhoneAuthErrorKind.rateLimited);
    }
  });

  test('demo happy path verifies the demo code', () async {
    final PhoneAuthRepository repo = PhoneAuthRepository(
      client: FakePhoneOtpClient(demoCode: '123456'),
    );
    await repo.requestOtp('+8801712345678');
    final AuthUser user = await repo.verifyOtp(
      rawPhone: '+8801712345678',
      token: '123456',
    );
    expect(user.phone, '+8801712345678');
  });
}
