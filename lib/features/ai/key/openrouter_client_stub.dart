/// OpenRouter call stub for packet B10 / R-23.
///
/// Contract: sends ONLY when the caller passes [key] explicitly at call
/// time. This class NEVER reads [ByokVault] (or any storage) itself, so it
/// cannot auto-attach the user key. No network is performed here; the stub
/// validates input and returns a canned demonstration response.
///
/// Production wiring (coordinator follow-up) replaces the body with a real
/// `https://openrouter.ai` POST using the passed key, keeping the same
/// explicit-key signature.
class OpenRouterClientStub {
  const OpenRouterClientStub();

  /// Explicit-key send. Throws [ArgumentError] when [key] is empty or
  /// [messages] is empty. Never reads secure storage.
  Future<String> sendWithKey({
    required String key,
    required List<Map<String, String>> messages,
  }) async {
    if (key.isEmpty) {
      throw ArgumentError(
        'Explicit user key required; stub never reads the vault.',
        'key',
      );
    }
    if (messages.isEmpty) {
      throw ArgumentError('At least one message is required.', 'messages');
    }
    // No network, no logging of key material. Canned demonstration reply.
    return 'STUB REWRITE (${messages.length} message(s)) — '
        'DEMONSTRATION ONLY, no network call made.';
  }
}
