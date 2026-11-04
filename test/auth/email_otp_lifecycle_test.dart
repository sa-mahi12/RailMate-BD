import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';

import 'email_otp_fakes.dart';

class _StreamClient extends EmailOtpFakeClient {
  final events = StreamController<AuthUser?>.broadcast();
  @override
  Stream<AuthUser?> authStateChanges() => events.stream;
}

const _confirmed = AuthUser(
  id: 'otp-user',
  email: 'otp@example.com',
  emailConfirmed: true,
);

void main() {
  for (final success in [true, false]) {
    test(
      'signed-out auth event supersedes late verify ${success ? 'success' : 'failure'}',
      () async {
        final client = _StreamClient()..verification = Completer<AuthUser?>();
        final auth = AuthState(repository: AuthRepository(client: client));
        addTearDown(auth.dispose);
        addTearDown(client.events.close);
        await auth.restore();
        final pending = auth.verifyCode(
          email: 'otp@example.com',
          token: '123456',
        );
        client.events.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(auth.status, AuthStatus.unauthenticated);
        if (success) {
          client.verification!.complete(_confirmed);
        } else {
          client.verification!.completeError(Exception('otp_expired'));
        }
        await pending;
        expect(auth.status, AuthStatus.unauthenticated);
        expect(auth.user, isNull);
        expect(auth.isBusy, isFalse);
      },
    );
  }

  test('signed-out auth event supersedes late resend failure', () async {
    final client = _StreamClient()..resend = Completer<void>();
    final auth = AuthState(repository: AuthRepository(client: client));
    addTearDown(auth.dispose);
    addTearDown(client.events.close);
    await auth.restore();
    final pending = auth.resendConfirmation('otp@example.com');
    client.events.add(null);
    await Future<void>.delayed(Duration.zero);
    client.resend!.completeError(Exception('provider failed'));
    await pending;
    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.user, isNull);
    expect(auth.errorMessage, isEmpty);
  });

  test(
    'explicit logout supersedes late verify success without an auth stream',
    () async {
      final client = EmailOtpFakeClient()
        ..verification = Completer<AuthUser?>();
      final auth = AuthState(repository: AuthRepository(client: client));
      addTearDown(auth.dispose);
      await auth.restore();
      final pending = auth.verifyCode(
        email: 'otp@example.com',
        token: '123456',
      );
      await auth.signOut();
      client.verification!.complete(_confirmed);
      await pending;
      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.user, isNull);
    },
  );

  test('verified auth event wins over a late OTP failure', () async {
    final client = _StreamClient()..verification = Completer<AuthUser?>();
    final auth = AuthState(repository: AuthRepository(client: client));
    addTearDown(auth.dispose);
    addTearDown(client.events.close);
    await auth.restore();
    final pending = auth.verifyCode(email: 'otp@example.com', token: '123456');
    client.events.add(_confirmed);
    await Future<void>.delayed(Duration.zero);
    client.verification!.completeError(Exception('otp_expired'));
    await pending;
    expect(auth.isAuthenticated, isTrue);
    expect(auth.errorMessage, isEmpty);
    expect(auth.isBusy, isFalse);
  });
}
