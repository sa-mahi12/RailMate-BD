import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';

class FakeAuthClient implements AuthClient {
  AuthUser? user;
  bool signedOut = false;
  final StreamController<AuthUser?> controller =
      StreamController<AuthUser?>.broadcast();

  @override
  Future<AuthUser?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? username,
  }) async {
    user = AuthUser(
      id: 'u1',
      email: email,
      emailConfirmed: false,
      fullName: fullName,
      phone: phone,
      username: username,
    );
    return user;
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    user = AuthUser(id: 'u1', email: email, emailConfirmed: true);
    return user;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    user = null;
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => controller.stream;

  @override
  Future<AuthUser?> refreshSession() async => user;

  @override
  Future<void> resendConfirmation(String email) async {}

  @override
  Future<AuthUser?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    user = AuthUser(id: 'u1', email: email, emailConfirmed: true);
    return user;
  }
}

void main() {
  test(
    'signUp trims email and stores metadata, returns unconfirmed user',
    () async {
      final FakeAuthClient fake = FakeAuthClient();
      final AuthRepository repo = AuthRepository(client: fake);
      final AuthUser? user = await repo.signUp(
        email: '  a@b.co  ',
        password: 's3cure!pw',
        fullName: 'Test User',
        username: 'tester',
      );
      expect(user!.email, 'a@b.co');
      expect(user.emailConfirmed, isFalse);
      expect(user.fullName, 'Test User');
    },
  );

  test('signUp rejects short password without network', () async {
    final AuthRepository repo = AuthRepository(client: FakeAuthClient());
    expect(
      () => repo.signUp(email: 'a@b.co', password: 'short'),
      throwsArgumentError,
    );
  });

  test('signIn rejects malformed email and empty password', () async {
    final AuthRepository repo = AuthRepository(client: FakeAuthClient());
    expect(
      () => repo.signIn(email: 'no-at-sign', password: 's3cure!pw'),
      throwsArgumentError,
    );
    expect(
      () => repo.signIn(email: 'a@b.co', password: ''),
      throwsArgumentError,
    );
  });

  test('verifyEmailOtp rejects non-6-digit token', () async {
    final AuthRepository repo = AuthRepository(client: FakeAuthClient());
    expect(
      () => repo.verifyEmailOtp(email: 'a@b.co', token: '123'),
      throwsArgumentError,
    );
  });
}
