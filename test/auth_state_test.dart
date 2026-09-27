import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/auth_repository.dart';
import 'package:railmate_bd/features/auth/auth_state.dart';

import 'auth_repository_test.dart' show FakeAuthClient;

void main() {
  test('restore with no session stays unauthenticated', () async {
    final AuthState state = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    await state.restore();
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.isAuthenticated, isFalse);
    state.unsubFromAuth();
    state.dispose();
  });

  test('signUp with unconfirmed user routes to needsVerification', () async {
    final AuthState state = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    await state.signUp(email: 'a@b.co', password: 's3cure!pw');
    expect(state.status, AuthStatus.needsVerification);
    expect(state.isAuthenticated, isFalse);
    state.unsubFromAuth();
    state.dispose();
  });

  test('signIn with confirmed user authenticates (guard passes)', () async {
    final AuthState state = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    await state.signIn(email: 'a@b.co', password: 's3cure!pw');
    expect(state.status, AuthStatus.authenticated);
    expect(state.isAuthenticated, isTrue);
    state.unsubFromAuth();
    state.dispose();
  });

  test('signOut clears session back to unauthenticated', () async {
    final AuthState state = AuthState(
      repository: AuthRepository(client: FakeAuthClient()),
    );
    await state.signIn(email: 'a@b.co', password: 's3cure!pw');
    await state.signOut();
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.user, isNull);
    state.unsubFromAuth();
    state.dispose();
  });
}
