import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../rewrite/rewrite_state.dart';

/// Real OpenRouter HTTPS client for F14 (packet B11 follow-up / R-23).
///
/// Contract (same explicit-key discipline as the B10 stub it replaces):
/// - Sends ONLY when the caller passes [key] explicitly at call time. This
///   class NEVER reads [ByokVault] (or any storage) itself, so it cannot
///   auto-attach the user key. Callers read the vault key inside the
///   explicit user-tap handler and pass it here.
/// - Called ONLY on explicit user action ('Improve Wording' tap or the
///   key-setup 'Test Connection' button), never on init/build.
/// - Key material is NEVER logged: no `print`/`debugPrint` of the key,
///   headers, request body, or response content anywhere in this file.
///   Thrown [RewriteRequestException] messages carry only the status code
///   and a short non-sensitive reason (a truncated provider snippet at
///   most — never the key).
class OpenRouterClient {
  /// OpenRouter OpenAI-compatible chat-completions endpoint.
  static const String endpoint =
      'https://openrouter.ai/api/v1/chat/completions';

  /// Cheap real instruction model used for board-draft rewrites.
  ///
  /// `meta-llama/llama-3.1-8b-instruct` is a low-cost open instruction-tuned
  /// model served on OpenRouter (verified on openrouter.ai at implementation
  /// time). 8B size keeps per-request cost minimal for a short rewrite task.
  static const String modelId = 'meta-llama/llama-3.1-8b-instruct';

  /// OpenRouter convention headers: attribution for the calling app.
  static const String appReferer = 'https://railmate-bd.app';
  static const String appTitle = 'RailMate BD';

  /// System instruction prepended to every rewrite request.
  static const String systemPrompt =
      'Rewrite the user draft for a railway board post. '
      'Return only the rewritten text.';

  final http.Client _http;

  /// Per-request timeout (also bounds the key-setup test connection).
  final Duration timeout;

  OpenRouterClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client();

  /// Explicit-key send. Throws [ArgumentError] when [key] is empty or
  /// [messages] is empty. Never reads secure storage. Returns the trimmed
  /// assistant text on HTTP 200; throws [RewriteRequestException] (with the
  /// genuine HTTP status when known) otherwise.
  Future<String> sendWithKey({
    required String key,
    required List<Map<String, String>> messages,
  }) async {
    if (key.isEmpty) {
      throw ArgumentError(
        'Explicit user key required; client never reads the vault.',
        'key',
      );
    }
    if (messages.isEmpty) {
      throw ArgumentError('At least one message is required.', 'messages');
    }
    final Map<String, Object?> body = <String, Object?>{
      'model': modelId,
      'messages': messages,
    };
    http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse(endpoint),
            headers: buildHeaders(key),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      // TimeoutException is recognised by the rewrite error mapper as a
      // network failure; the message marker keeps that working even though
      // the runtime type is wrapped here.
      throw const RewriteRequestException(
        'request timed out — connection failed',
      );
    } catch (e) {
      final int? status = _statusOf(e);
      if (e is RewriteRequestException) rethrow;
      throw RewriteRequestException(
        'connection failed: ${e.runtimeType}',
        statusCode: status,
      );
    }
    return _handleResponse(res);
  }

  /// Convenience for the board rewrite flow: builds the system + draft
  /// messages and returns the improved wording. Throws [ArgumentError] on a
  /// blank draft so no call is ever made with empty text.
  Future<String> improveDraft({
    required String key,
    required String draft,
  }) async {
    if (draft.trim().isEmpty) {
      throw ArgumentError('Draft must not be empty.', 'draft');
    }
    return sendWithKey(
      key: key,
      messages: <Map<String, String>>[
        const <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': draft},
      ],
    );
  }

  /// Pure request-header builder (unit-testable without network).
  ///
  /// Includes the OpenRouter-convention `HTTP-Referer` + `X-Title` headers.
  /// The test suite asserts header presence with a fake `'test-key'` value —
  /// never a real user key.
  static Map<String, String> buildHeaders(String key) {
    return <String, String>{
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'HTTP-Referer': appReferer,
      'X-Title': appTitle,
    };
  }

  /// Pure request-body builder for one draft (unit-testable without network).
  static Map<String, Object?> buildBody(String draft) {
    return <String, Object?>{
      'model': modelId,
      'messages': <Map<String, String>>[
        const <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': draft},
      ],
    };
  }

  /// Pure response parser for the chat-completions shape.
  ///
  /// Returns the trimmed assistant content. Throws [RewriteRequestException]
  /// (no status) when `choices[0].message.content` is missing or blank, so
  /// the UI can show an honest "could not improve" error and the draft stays
  /// untouched. Never logs the payload.
  static String parseCompletionBody(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const RewriteRequestException(
        'empty response — could not improve this draft',
      );
    }
    final Object? choices = (decoded as Map<String, dynamic>)['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const RewriteRequestException(
        'empty response — could not improve this draft',
      );
    }
    final Object? first = choices.first;
    if (first is! Map) {
      throw const RewriteRequestException(
        'empty response — could not improve this draft',
      );
    }
    final Object? message = (first as Map<String, dynamic>)['message'];
    if (message is! Map) {
      throw const RewriteRequestException(
        'empty response — could not improve this draft',
      );
    }
    final Object? content = (message as Map<String, dynamic>)['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const RewriteRequestException(
        'empty response — could not improve this draft',
      );
    }
    return content.trim();
  }

  /// Maps an HTTP response to either the parsed wording or an honest
  /// [RewriteRequestException] carrying the genuine status code.
  static String _handleResponse(http.Response res) {
    switch (res.statusCode) {
      case 200:
        try {
          return parseCompletionBody(res.body);
        } on FormatException {
          throw const RewriteRequestException(
            'empty response — could not improve this draft',
          );
        }
      case 401:
        throw const RewriteRequestException(
          'invalid key (401)',
          statusCode: 401,
        );
      case 402:
        throw const RewriteRequestException(
          'payment required / quota exhausted (402)',
          statusCode: 402,
        );
      case 429:
        throw const RewriteRequestException(
          'rate limited / quota exceeded (429)',
          statusCode: 429,
        );
      default:
        // Truncated provider snippet only; never key material (the key is
        // in the request headers, never echoed into the response body).
        final String snippet = res.body.length > 200
            ? '${res.body.substring(0, 200)}…'
            : res.body;
        throw RewriteRequestException(
          'request failed (${res.statusCode}): $snippet',
          statusCode: res.statusCode,
        );
    }
  }

  /// Best-effort status extraction from wrapped transport errors.
  static int? _statusOf(Object error) {
    try {
      final dynamic status = (error as dynamic).statusCode;
      if (status is int) return status;
    } catch (_) {
      // No statusCode member — genuinely unknown.
    }
    return null;
  }
}
