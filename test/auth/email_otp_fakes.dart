import 'dart:async';

import 'package:railmate_bd/features/auth/auth_repository.dart';

import '../f19_fakes.dart';

/// External auth boundary only; UI, repository and state remain real.
class EmailOtpFakeClient extends F19AuthClient {
  EmailOtpFakeClient()
    : super(
        stubUser: const AuthUser(
          id: 'otp-user',
          email: 'otp@example.com',
          emailConfirmed: false,
        ),
      );

  int verifications = 0;
  int resends = 0;
  String? submittedEmail;
  String? submittedToken;
  Object? verifyError;
  Object? resendError;
  Completer<AuthUser?>? verification;
  Completer<void>? resend;
  bool returnNoUser = false;

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifications++;
    submittedEmail = email;
    submittedToken = token;
    if (verification != null) return verification!.future;
    if (verifyError != null) throw verifyError!;
    if (returnNoUser) return null;
    return AuthUser(id: 'otp-user', email: email, emailConfirmed: true);
  }

  @override
  Future<void> resendConfirmation(String email) async {
    resends++;
    if (resend != null) return resend!.future;
    if (resendError != null) throw resendError!;
  }
}
