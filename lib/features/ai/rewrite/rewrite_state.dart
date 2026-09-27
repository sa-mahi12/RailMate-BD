import 'package:flutter/foundation.dart';

/// Rewrite request status for one generative rewrite (packet B11 / R-23).
///
/// - [idle]: nothing requested (or suggestion accepted/rejected).
/// - [loading]: one explicit request in flight.
/// - [ready]: a suggestion is available and awaits explicit Accept/Reject.
/// - [error]: the request failed; see [RewriteState.errorMessage].
enum RewriteStatus { idle, loading, ready, error }

/// Explicit key read, injected so tests use a fake. Production wiring
/// passes `vault.readKey` (B10 [ByokVault]); this state never touches
/// secure storage itself.
typedef ReadRewriteKey = Future<String?> Function();

/// Explicit-key send, injected so tests use a fake backend. Production
/// wiring passes a closure over
/// `OpenRouterClientStub.sendWithKey(key: ..., messages: ...)` (B10),
/// keeping the exact explicit-key signature: the key travels only as the
/// `key:` argument of one user-tapped request.
typedef SendRewrite = Future<String> Function({
  required String key,
  required String draft,
});

/// Provider failure surfaced by a rewrite backend.
///
/// [statusCode] carries the HTTP status when the backend knows it
/// (401 = bad key, 429 = quota). A backend that only has a message may
/// leave it null; [mapRewriteError] then falls back to message sniffing.
class RewriteRequestException implements Exception {
  final int? statusCode;
  final String message;

  const RewriteRequestException(this.message, {this.statusCode});

  @override
  String toString() =>
      'RewriteRequestException(${statusCode ?? 'no-status'}): $message';
}

/// Maps a backend failure to the user-facing B11 error text.
///
/// Contract: 401 → key invalid, 429 → quota exceeded, network → connection
/// failed. Anything unrecognized maps to a neutral retry message (never
/// leaks key material or raw provider payloads).
String mapRewriteError(Object error) {
  int? code;
  if (error is RewriteRequestException) {
    code = error.statusCode;
  } else {
    try {
      final dynamic status = (error as dynamic).statusCode;
      if (status is int) code = status;
    } catch (_) {
      // No statusCode member — fall through to message sniffing.
    }
  }
  final text = error.toString();
  if (code == 401 || _mentions(text, const ['401', 'unauthorized'])) {
    return 'AI rewrite failed: key invalid.';
  }
  if (code == 429 ||
      _mentions(text, const ['429', 'too many requests', 'quota exceeded'])) {
    return 'AI rewrite failed: quota exceeded, try later.';
  }
  if (_looksLikeNetworkError(error, text)) {
    return 'AI rewrite failed: connection failed.';
  }
  return 'AI rewrite failed. Try again later.';
}

bool _mentions(String text, List<String> needles) {
  final lower = text.toLowerCase();
  return needles.any((n) => lower.contains(n));
}

/// Matches common Dart/Flutter network failure shapes without importing
/// any HTTP package (this slice adds no new dependencies).
bool _looksLikeNetworkError(Object error, String text) {
  final runtime = error.runtimeType.toString().toLowerCase();
  if (runtime.contains('socketexception') ||
      runtime.contains('clientexception') ||
      runtime.contains('httpexception') ||
      runtime.contains('timeoutexception')) {
    return true;
  }
  return _mentions(text, const [
    'socketexception',
    'connection failed',
    'connection refused',
    'network is unreachable',
    'failed host lookup',
    'timed out',
  ]);
}

/// State for one generative rewrite of the user's own draft
/// (packet B11 / R-23).
///
/// Binding stop-conditions enforced here:
/// - NEVER auto-commits text: [accept] only returns the suggestion to the
///   caller callback and clears local state; it never writes to any store,
///   post, or network. [reject] discards the suggestion.
/// - The key is read via [ReadRewriteKey] and sent via [SendRewrite] ONLY
///   inside [improve], which runs solely on the explicit 'Improve Wording'
///   tap and additionally requires the single-use per-request [consent]
///   checkbox (B10 screen pattern).
/// - Core app works without a key: when [readKey] yields no key, [improve]
///   lands in [RewriteStatus.error] with a setup prompt instead of calling
///   [send], and the widget disables the entry point.
/// - No live calls from this slice beyond the injected backend; production
///   wiring uses the B10 stub (canned DEMONSTRATION ONLY reply).
class RewriteState extends ChangeNotifier {
  // Field is private (_draft) so an initializing formal cannot reuse the
  // public parameter name `draft`.
  // ignore: prefer_initializing_formals
  RewriteState({required String draft}) : _draft = draft;

  String _draft;

  /// Current request status.
  RewriteStatus status = RewriteStatus.idle;

  /// Provider suggestion; non-null only while [status] is [RewriteStatus.ready].
  String? suggestion;

  /// User-facing error text; non-null only while [status] is [RewriteStatus.error].
  String? errorMessage;

  /// Per-request consent ('Send my key with this request only').
  /// Single-use: reset to false after every [improve] attempt.
  bool consent = false;

  /// Current draft text.
  String get draft => _draft;

  bool get isLoading => status == RewriteStatus.loading;

  bool get hasSuggestion =>
      status == RewriteStatus.ready && (suggestion ?? '').isNotEmpty;

  void updateDraft(String value) {
    if (value == _draft) return;
    _draft = value;
    notifyListeners();
  }

  void setConsent(bool value) {
    if (value == consent) return;
    consent = value;
    notifyListeners();
  }

  /// Runs one explicit rewrite request. No-op while a request is in flight.
  ///
  /// Order: consent gate → draft gate → key read (no key = setup-prompt
  /// error, [send] never called) → [send] → ready/error mapping.
  Future<void> improve({
    required ReadRewriteKey readKey,
    required SendRewrite send,
  }) async {
    if (isLoading) return;
    if (!consent) {
      status = RewriteStatus.error;
      suggestion = null;
      errorMessage =
          'Tick "Send my key with this request only" to allow this one call.';
      notifyListeners();
      return;
    }
    if (_draft.trim().isEmpty) {
      status = RewriteStatus.error;
      suggestion = null;
      errorMessage = 'Write a draft first.';
      notifyListeners();
      return;
    }
    status = RewriteStatus.loading;
    suggestion = null;
    errorMessage = null;
    notifyListeners();
    try {
      final key = await readKey();
      if (key == null || key.isEmpty) {
        status = RewriteStatus.error;
        errorMessage =
            'No AI key saved. Add one in AI Settings to enable rewrite.';
        return;
      }
      final out = await send(key: key, draft: _draft);
      suggestion = out;
      status = RewriteStatus.ready;
    } catch (e) {
      suggestion = null;
      status = RewriteStatus.error;
      errorMessage = mapRewriteError(e);
    } finally {
      // Consent is single-use even on failure: each request needs a fresh tick.
      consent = false;
      notifyListeners();
    }
  }

  /// Accepts the suggestion: returns it so the caller can invoke its
  /// `onAccepted` callback, then clears local state. NEVER writes anywhere
  /// itself (no storage, no post update, no network). Returns null when
  /// there is no suggestion to accept.
  String? accept() {
    final out = suggestion;
    suggestion = null;
    errorMessage = null;
    status = RewriteStatus.idle;
    notifyListeners();
    return out;
  }

  /// Discards the suggestion without invoking any callback or write.
  void reject() {
    suggestion = null;
    errorMessage = null;
    status = RewriteStatus.idle;
    notifyListeners();
  }
}
