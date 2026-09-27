import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/ai/key/byok_vault.dart';
import 'package:railmate_bd/features/ai/key/openrouter_client_stub.dart';

class FakeBackend implements KeyStorageBackend {
  final Map<String, String?> store = {};
  @override
  Future<void> write({required String key, required String? value}) async {
    store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => store[key];
  @override
  Future<void> delete({required String key}) async {
    store.remove(key);
  }

  @override
  Future<bool> containsKey({required String key}) async =>
      store.containsKey(key);
}

void main() {
  test('save->has->read roundtrip', () async {
    final vault = ByokVault(backend: FakeBackend(), accountId: 'u1');
    expect(await vault.hasKey(), isFalse);
    await vault.saveKey('sk-or-testkey1234');
    expect(await vault.hasKey(), isTrue);
    expect(await vault.readKey(), 'sk-or-testkey1234');
  });
  test('remove clears storage and cache', () async {
    final backend = FakeBackend();
    final vault = ByokVault(backend: backend, accountId: 'u1');
    await vault.saveKey('sk-or-testkey1234');
    await vault.removeKey();
    expect(await vault.hasKey(), isFalse);
    expect(await vault.readKey(), isNull);
    expect(backend.store, isEmpty);
  });
  test('logout isolates (cache + storage cleared)', () async {
    final backend = FakeBackend();
    final vault = ByokVault(backend: backend, accountId: 'u1');
    await vault.saveKey('sk-or-testkey1234');
    expect(await vault.readKey(), isNotNull); // warms cache
    await vault.logout();
    expect(await vault.hasKey(), isFalse);
    expect(await vault.readKey(), isNull);
    expect(backend.store, isEmpty);
  });
  test('accounts are isolated by storage key', () async {
    final backend = FakeBackend();
    final a = ByokVault(backend: backend, accountId: 'u1');
    final b = ByokVault(backend: backend, accountId: 'u2');
    await a.saveKey('key-for-u1');
    expect(await b.hasKey(), isFalse);
    expect(ByokVault.storageKeyFor('u1'), isNot(ByokVault.storageKeyFor('u2')));
  });
  test('masked preview leaks nothing', () {
    const full = 'sk-or-abcdefgh1234';
    final preview = ByokVault.maskedPreviewOf(full);
    expect(preview, endsWith('1234'));
    expect(preview.contains(full), isFalse);
    expect(preview.length, lessThan(full.length));
    expect(ByokVault.maskedPreviewOf(null), 'not set');
    expect(ByokVault.maskedPreviewOf(''), 'not set');
  });
  test('stub refuses empty key and empty messages', () async {
    const stub = OpenRouterClientStub();
    expect(
      () => stub.sendWithKey(
        key: '',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => stub.sendWithKey(key: 'k', messages: const []),
      throwsArgumentError,
    );
  });
  test('stub sends only with explicit key (no vault read)', () async {
    const stub = OpenRouterClientStub();
    final reply = await stub.sendWithKey(
      key: 'explicit-key',
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );
    expect(reply, contains('DEMONSTRATION ONLY'));
  });
}
