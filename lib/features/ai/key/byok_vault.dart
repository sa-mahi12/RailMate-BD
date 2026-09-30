import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal storage-backend abstraction so [ByokVault] can be unit-tested
/// with a fake without a device keystore.
///
/// Production wiring uses [SecureStorageBackend] (flutter_secure_storage,
/// Android Keystore). Tests inject a fake implementing [KeyStorageBackend].
abstract class KeyStorageBackend {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<bool> containsKey({required String key});
}

/// Production backend delegating to flutter_secure_storage.
///
/// Android: EncryptedSharedPreferences backed by the Android Keystore
/// (RSA OAEP + AES-GCM default in flutter_secure_storage v10+).
class SecureStorageBackend implements KeyStorageBackend {
  final FlutterSecureStorage storage;

  SecureStorageBackend({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> write({required String key, required String? value}) =>
      storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => storage.read(key: key);

  @override
  Future<void> delete({required String key}) => storage.delete(key: key);

  @override
  Future<bool> containsKey({required String key}) =>
      storage.containsKey(key: key);
}

/// User-controlled OpenRouter key vault (packet B10 / R-23).
///
/// Rules (binding stop-conditions):
/// - No developer fallback key: no hardcoded/default key anywhere.
/// - The key is sent to OpenRouter ONLY on explicit user action: callers
///   must read the key here and pass it to
///   `OpenRouterClient.sendWithKey(key: ..., ...)` (F14 real HTTPS client;
///   B10 stub kept for contract tests) at call time.
///   This class never performs network calls itself.
/// - [removeKey]/[logout] isolate the account: delete from secure storage
///   AND clear the in-memory cache.
/// - Key material is NEVER logged/printed. Only [maskedPreviewOf] (last 4
///   chars) may reach the UI/logs.
class ByokVault {
  /// Single base key name in secure storage.
  static const String baseKey = 'openrouter_user_key';

  final KeyStorageBackend backend;

  /// Account scope: storage key is prefixed per user id so two accounts
  /// on one device never share key material.
  final String? accountId;

  String? _cachedKey;

  ByokVault({required this.backend, this.accountId});

  /// Storage key for an account scope. Empty/null account uses [baseKey].
  static String storageKeyFor(String? account) {
    if (account == null || account.isEmpty) return baseKey;
    return '${account}__$baseKey';
  }

  /// Storage key for this vault instance.
  String get storageKey => storageKeyFor(accountId);

  /// Persist the user-supplied [key]. Throws [ArgumentError] on empty input.
  /// Never logs key material.
  Future<void> saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Key must not be empty.', 'key');
    }
    await backend.write(key: storageKey, value: trimmed);
    _cachedKey = trimmed;
  }

  /// Read the stored key, or null when absent. Populates the in-memory
  /// cache on hit.
  Future<String?> readKey() async {
    final cached = _cachedKey;
    if (cached != null) {
      return cached;
    }
    final stored = await backend.read(key: storageKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    _cachedKey = stored;
    return stored;
  }

  /// True when a key is cached or present in secure storage.
  Future<bool> hasKey() async {
    if (_cachedKey != null) {
      return true;
    }
    return backend.containsKey(key: storageKey);
  }

  /// Delete the key from secure storage and clear the in-memory cache.
  Future<void> removeKey() async {
    await backend.delete(key: storageKey);
    _cachedKey = null;
  }

  /// Account logout isolation: clears cache AND storage (same as
  /// [removeKey], named for the auth-layer call site).
  Future<void> logout() async {
    await backend.delete(key: storageKey);
    _cachedKey = null;
  }

  /// Masked preview safe for UI display. Exposes at most the last 4
  /// characters, e.g. `••••abcd`. Returns `'not set'` for null/empty.
  /// Pure function: safe to assert in tests that it never leaks the full key.
  static String maskedPreviewOf(String? key) {
    if (key == null || key.isEmpty) {
      return 'not set';
    }
    const mask = '••••';
    if (key.length <= 4) {
      return '$mask$key'.substring(0, mask.length + key.length);
    }
    return '$mask${key.substring(key.length - 4)}';
  }
}
