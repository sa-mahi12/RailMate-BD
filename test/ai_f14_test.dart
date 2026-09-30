import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:railmate_bd/features/ai/key/openrouter_client.dart';
import 'package:railmate_bd/features/ai/rewrite/rewrite_state.dart';

/// F14 — real OpenRouter call path for Improve Wording (BYOK), hermetic.
///
/// Every test uses a fake `http.Client` ([MockClient]) or pure helpers —
/// no network, no real key. The only key value asserted anywhere is the
/// fake `'test-key'`.
void main() {
  const fakeKey = 'test-key';

  String goodBody(String text) => jsonEncode(<String, Object?>{
    'id': 'gen-f14',
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, String>{'role': 'assistant', 'content': text},
      },
    ],
  });

  OpenRouterClient clientFor(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 5),
  }) => OpenRouterClient(httpClient: MockClient(handler), timeout: timeout);

  group('request building (fake test-key only)', () {
    test('posts to the OpenRouter chat-completions URL', () async {
      http.Request? seen;
      final client = clientFor((http.Request req) async {
        seen = req;
        return http.Response(goodBody('polished'), 200);
      });
      await client.improveDraft(key: fakeKey, draft: 'rough draft');
      expect(seen, isNotNull);
      expect(seen!.url.toString(), OpenRouterClient.endpoint);
      expect(
        seen!.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(seen!.method, 'POST');
    });

    test('headers carry auth + OpenRouter convention headers', () async {
      http.Request? seen;
      final client = clientFor((http.Request req) async {
        seen = req;
        return http.Response(goodBody('polished'), 200);
      });
      await client.improveDraft(key: fakeKey, draft: 'rough draft');
      final headers = seen!.headers;
      expect(headers['Authorization'], 'Bearer $fakeKey');
      expect(headers['Content-Type'], contains('application/json'));
      expect(headers['HTTP-Referer'], isNotNull);
      expect(headers['HTTP-Referer'], isNotEmpty);
      expect(headers['X-Title'], isNotNull);
      expect(headers['X-Title'], isNotEmpty);
    });

    test('body carries the real model id and the draft text', () async {
      http.Request? seen;
      final client = clientFor((http.Request req) async {
        seen = req;
        return http.Response(goodBody('polished'), 200);
      });
      await client.improveDraft(key: fakeKey, draft: 'station tip rough');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['model'], OpenRouterClient.modelId);
      final messages = body['messages'] as List;
      expect(messages.length, 2);
      expect(
        (messages.last as Map<String, dynamic>)['content'],
        'station tip rough',
      );
    });

    test('pure builders agree with the live request shape', () {
      final headers = OpenRouterClient.buildHeaders(fakeKey);
      expect(headers['Authorization'], 'Bearer $fakeKey');
      expect(headers.containsKey('HTTP-Referer'), isTrue);
      expect(headers.containsKey('X-Title'), isTrue);
      final body = OpenRouterClient.buildBody('hello');
      expect(body['model'], OpenRouterClient.modelId);
      expect(jsonEncode(body), contains('hello'));
    });

    test(
      'empty key / empty messages / empty draft never reach the network',
      () async {
        var calls = 0;
        final client = clientFor((http.Request req) async {
          calls++;
          return http.Response(goodBody('x'), 200);
        });
        await expectLater(
          client.sendWithKey(
            key: '',
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
          ),
          throwsArgumentError,
        );
        await expectLater(
          client.sendWithKey(key: fakeKey, messages: const []),
          throwsArgumentError,
        );
        await expectLater(
          client.improveDraft(key: fakeKey, draft: '   '),
          throwsArgumentError,
        );
        expect(calls, 0);
      },
    );
  });

  group('response parsing', () {
    test('good shape returns the trimmed wording', () async {
      final client = clientFor(
        (_) async => http.Response(goodBody('  polished draft  '), 200),
      );
      expect(
        await client.improveDraft(key: fakeKey, draft: 'rough'),
        'polished draft',
      );
    });

    test('missing choices → honest could-not-improve error', () async {
      final client = clientFor(
        (_) async => http.Response(jsonEncode({'id': 'gen-x'}), 200),
      );
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect(err, isA<RewriteRequestException>());
      expect(mapRewriteError(err), contains('could not improve'));
    });

    test('empty content → honest could-not-improve error', () async {
      final client = clientFor(
        (_) async => http.Response(goodBody('   '), 200),
      );
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect(err, isA<RewriteRequestException>());
      expect(mapRewriteError(err), contains('could not improve'));
    });

    test('non-JSON body → honest could-not-improve error', () async {
      final client = clientFor((_) async => http.Response('not json', 200));
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect(err, isA<RewriteRequestException>());
      expect(mapRewriteError(err), contains('could not improve'));
    });
  });

  group('error mapping', () {
    test('401 → invalid key with status preserved', () async {
      final client = clientFor((_) async => http.Response('unauthorized', 401));
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect(err, isA<RewriteRequestException>());
      expect((err as RewriteRequestException).statusCode, 401);
      expect(mapRewriteError(err), contains('key invalid'));
    });

    test('402 → honest quota message', () async {
      final client = clientFor(
        (_) async => http.Response('insufficient credits', 402),
      );
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect((err as RewriteRequestException).statusCode, 402);
      expect(mapRewriteError(err), contains('quota exhausted'));
    });

    test('429 → honest rate/quota message', () async {
      final client = clientFor((_) async => http.Response('slow down', 429));
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect((err as RewriteRequestException).statusCode, 429);
      expect(mapRewriteError(err), contains('quota exceeded'));
    });

    test('5xx → neutral retry, draft untouched at state level', () async {
      final client = clientFor(
        (_) async => http.Response('upstream boom', 502),
      );
      final state = RewriteState(draft: 'keep me');
      state.setConsent(true);
      await state.improve(
        readKey: () async => fakeKey,
        send: ({required String key, required String draft}) =>
            client.improveDraft(key: key, draft: draft),
      );
      expect(state.status, RewriteStatus.error);
      expect(state.suggestion, isNull);
      expect(state.draft, 'keep me');
      expect(state.errorMessage, isNotNull);
    });

    test('transport failure → retryable connection message', () async {
      final client = clientFor((_) async {
        throw http.ClientException('socket blew up');
      });
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect(err, isA<RewriteRequestException>());
      expect(mapRewriteError(err), contains('connection failed'));
    });

    test('timeout → retryable connection message', () async {
      final client = clientFor((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response(goodBody('too late'), 200);
      }, timeout: const Duration(milliseconds: 50));
      final err = await captureThrow(
        () => client.improveDraft(key: fakeKey, draft: 'rough'),
      );
      expect(err, isA<RewriteRequestException>());
      expect(mapRewriteError(err), contains('connection failed'));
    });
  });

  group('state gating (no-key, consent, success)', () {
    test('no key → setup nudge, backend never called', () async {
      var calls = 0;
      final client = clientFor((_) async {
        calls++;
        return http.Response(goodBody('unreachable'), 200);
      });
      final state = RewriteState(draft: 'some draft');
      state.setConsent(true);
      await state.improve(
        readKey: () async => null,
        send: ({required String key, required String draft}) =>
            client.improveDraft(key: key, draft: draft),
      );
      expect(calls, 0);
      expect(state.status, RewriteStatus.error);
      expect(state.errorMessage, contains('AI Settings'));
    });

    test('blank draft → no call (state gate)', () async {
      var calls = 0;
      final client = clientFor((_) async {
        calls++;
        return http.Response(goodBody('unreachable'), 200);
      });
      final state = RewriteState(draft: '   ');
      state.setConsent(true);
      await state.improve(
        readKey: () async => fakeKey,
        send: ({required String key, required String draft}) =>
            client.improveDraft(key: key, draft: draft),
      );
      expect(calls, 0);
      expect(state.status, RewriteStatus.error);
    });

    test('success → suggestion ready for explicit host apply', () async {
      final client = clientFor(
        (_) async => http.Response(goodBody('polished wording'), 200),
      );
      final state = RewriteState(draft: 'rough');
      state.setConsent(true);
      await state.improve(
        readKey: () async => fakeKey,
        send: ({required String key, required String draft}) =>
            client.improveDraft(key: key, draft: draft),
      );
      expect(state.status, RewriteStatus.ready);
      expect(state.suggestion, 'polished wording');
      // Host applies on Accept; state itself writes nowhere.
      expect(state.accept(), 'polished wording');
    });
  });

  group('key-handling audit', () {
    test('thrown errors never contain the key value', () async {
      final failures = <Object>[
        await captureThrow(
          () =>
              clientFor((_) async => http.Response('unauthorized', 401))
                  .improveDraft(key: fakeKey, draft: 'rough'),
        ),
        await captureThrow(
          () =>
              clientFor((_) async => http.Response('no credits', 402))
                  .improveDraft(key: fakeKey, draft: 'rough'),
        ),
        await captureThrow(
          () =>
              clientFor((_) async => http.Response('slow', 429))
                  .improveDraft(key: fakeKey, draft: 'rough'),
        ),
        await captureThrow(
          () =>
              clientFor((_) async => http.Response('boom', 500))
                  .improveDraft(key: fakeKey, draft: 'rough'),
        ),
        await captureThrow(
          () =>
              clientFor((_) async => http.Response('{}', 200))
                  .improveDraft(key: fakeKey, draft: 'rough'),
        ),
        await captureThrow(
          () => clientFor((_) async {
            throw http.ClientException('down');
          }).improveDraft(key: fakeKey, draft: 'rough'),
        ),
      ];
      for (final err in failures) {
        expect(
          err.toString(),
          isNot(contains(fakeKey)),
          reason: 'error leaks key: $err',
        );
        expect(
          mapRewriteError(err),
          isNot(contains(fakeKey)),
          reason: 'mapped message leaks key: $err',
        );
      }
    });
  });
}

/// Runs [fn] and returns the thrown error (fails the test when nothing throws).
Future<Object> captureThrow(Future<Object?> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    return e;
  }
  fail('Expected an exception but none was thrown.');
}
