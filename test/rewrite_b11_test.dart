import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/ai/rewrite/rewrite_state.dart';

void main() {
  RewriteState stateWith({String draft = 'hello world'}) =>
      RewriteState(draft: draft);

  test('accept returns text and clears state, writes nothing', () async {
    final s = stateWith();
    s.setConsent(true);
    await s.improve(
      readKey: () async => 'user-key',
      send: ({required String key, required String draft}) async {
        expect(key, 'user-key');
        return 'polished $draft';
      },
    );
    expect(s.status, RewriteStatus.ready);
    expect(s.suggestion, 'polished hello world');
    final out = s.accept();
    expect(out, 'polished hello world');
    expect(s.status, RewriteStatus.idle);
    expect(s.suggestion, isNull);
    expect(s.errorMessage, isNull);
  });

  test('reject discards suggestion without callback side effects', () async {
    final s = stateWith();
    s.setConsent(true);
    await s.improve(
      readKey: () async => 'user-key',
      send: ({required String key, required String draft}) async => 'better',
    );
    expect(s.hasSuggestion, isTrue);
    s.reject();
    expect(s.status, RewriteStatus.idle);
    expect(s.suggestion, isNull);
    expect(s.accept(), isNull); // nothing left to accept
  });

  test('401 maps to key invalid', () async {
    final s = stateWith();
    s.setConsent(true);
    await s.improve(
      readKey: () async => 'bad-key',
      send: ({required String key, required String draft}) async {
        throw const RewriteRequestException('unauthorized', statusCode: 401);
      },
    );
    expect(s.status, RewriteStatus.error);
    expect(s.errorMessage, contains('key invalid'));
    expect(s.suggestion, isNull);
  });

  test('429 maps to quota exceeded', () async {
    final s = stateWith();
    s.setConsent(true);
    await s.improve(
      readKey: () async => 'user-key',
      send: ({required String key, required String draft}) async {
        throw const RewriteRequestException('slow down', statusCode: 429);
      },
    );
    expect(s.status, RewriteStatus.error);
    expect(s.errorMessage, contains('quota exceeded, try later'));
  });

  test(
    'no-key initial state never calls send (core works without key)',
    () async {
      final s = stateWith();
      var sendCalled = false;
      s.setConsent(true);
      await s.improve(
        readKey: () async => null,
        send: ({required String key, required String draft}) async {
          sendCalled = true;
          return 'unreachable';
        },
      );
      expect(sendCalled, isFalse);
      expect(s.status, RewriteStatus.error);
      expect(s.errorMessage, contains('AI Settings'));
    },
  );

  test('no consent means no send', () async {
    final s = stateWith();
    var sendCalled = false;
    await s.improve(
      readKey: () async => 'user-key',
      send: ({required String key, required String draft}) async {
        sendCalled = true;
        return 'unreachable';
      },
    );
    expect(sendCalled, isFalse);
    expect(s.status, RewriteStatus.error);
  });

  test('consent is single-use: second improve needs a fresh tick', () async {
    final s = stateWith();
    s.setConsent(true);
    await s.improve(
      readKey: () async => 'user-key',
      send: ({required String key, required String draft}) async => 'v1',
    );
    expect(s.consent, isFalse);
    var sendCalled = false;
    await s.improve(
      readKey: () async => 'user-key',
      send: ({required String key, required String draft}) async {
        sendCalled = true;
        return 'v2';
      },
    );
    expect(sendCalled, isFalse); // consent was consumed by the first request
  });
}
