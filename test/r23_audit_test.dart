import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/ai/key/byok_vault.dart';
import 'package:railmate_bd/features/ai/key/openrouter_client.dart';
import 'package:railmate_bd/features/ai/rewrite/rewrite_state.dart';

/// R-23 (BYOK generative AI) independent audit tests.
///
/// What they prove: the key is only read on an explicit user action, removing
/// it disables the feature, no key material reaches logs or user-facing error
/// text, the network call is bounded by a timeout, and the booking code has no
/// dependency on the AI feature. What they do NOT prove: a successful live
/// OpenRouter request — that needs an owner key (docs/owner/openrouter-demo.md).
class MemoryBackend implements KeyStorageBackend {
  final Map<String, String?> values = <String, String?>{};

  @override
  Future<void> write({required String key, required String? value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<bool> containsKey({required String key}) async => values[key] != null;
}

String? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}

Iterable<File> _dartFiles(String relative) {
  final String root = _repoRoot() ?? '';
  final Directory dir = Directory('$root/$relative');
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'));
}

void main() {
  group('key lifecycle', () {
    test('removing the key disables a rewrite instead of sending', () async {
      final MemoryBackend backend = MemoryBackend();
      final ByokVault vault = ByokVault(backend: backend, accountId: 'u1');
      await vault.saveKey('sk-or-v1-TESTONLYabcdefgh1234');
      expect(await vault.hasKey(), isTrue);

      await vault.removeKey();
      expect(await vault.hasKey(), isFalse);
      expect(await vault.readKey(), isNull);

      final RewriteState state = RewriteState(draft: 'A draft about trains.');
      state.setConsent(true);
      var sent = false;
      await state.improve(
        readKey: vault.readKey,
        send: ({required String key, required String draft}) async {
          sent = true;
          return 'should never run';
        },
      );

      expect(sent, isFalse, reason: 'no key means no request');
      expect(state.status, RewriteStatus.error);
      expect(state.errorMessage, contains('AI Settings'));
      expect(state.hasSuggestion, isFalse);
    });

    test('logout isolation clears the stored key', () async {
      final MemoryBackend backend = MemoryBackend();
      final ByokVault vault = ByokVault(backend: backend, accountId: 'u1');
      await vault.saveKey('sk-or-v1-TESTONLYabcdefgh1234');
      await vault.logout();
      expect(await vault.readKey(), isNull);
      expect(
        backend.values.containsKey(ByokVault.storageKeyFor('u1')),
        isFalse,
      );
    });

    test('a short key is masked entirely', () {
      expect(ByokVault.maskedPreviewOf('abcd'), '••••');
      expect(ByokVault.maskedPreviewOf('abcdefgh'), '••••');
      expect(
        ByokVault.maskedPreviewOf('sk-or-v1-abcdefgh1234'),
        endsWith('1234'),
      );
    });
  });

  group('request handling', () {
    test('a provider failure never echoes the key to the user', () async {
      const String key = 'sk-or-v1-SECRETSECRETSECRET9999';
      final RewriteState state = RewriteState(draft: 'A draft.');
      state.setConsent(true);
      await state.improve(
        readKey: () async => key,
        send: ({required String key, required String draft}) async {
          throw RewriteRequestException(
            'request failed (500): $key leaked into a fake body',
            statusCode: 500,
          );
        },
      );
      expect(state.status, RewriteStatus.error);
      expect(state.errorMessage, isNot(contains(key)));
      expect(state.errorMessage, contains('Try again later'));
    });

    test('a failed request leaves the draft untouched', () async {
      final RewriteState state = RewriteState(draft: 'Original wording.');
      state.setConsent(true);
      await state.improve(
        readKey: () async => 'sk-or-v1-TESTONLYabcdefgh1234',
        send: ({required String key, required String draft}) async {
          throw RewriteRequestException('request timed out', statusCode: 503);
        },
      );
      expect(state.draft, 'Original wording.');
      expect(state.hasSuggestion, isFalse);
      expect(state.consent, isFalse, reason: 'consent is single-use');
    });

    test('the network call is bounded by a finite timeout', () {
      final OpenRouterClient client = OpenRouterClient();
      expect(client.timeout, const Duration(seconds: 20));
      expect(client.timeout.inSeconds, greaterThan(0));
    });

    test('the client refuses to send without an explicit key', () async {
      final OpenRouterClient client = OpenRouterClient();
      expect(
        () => client.sendWithKey(
          key: '',
          messages: const <Map<String, String>>[
            <String, String>{'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a blank draft never reaches the provider', () async {
      final OpenRouterClient client = OpenRouterClient();
      expect(
        () => client.improveDraft(key: 'k', draft: '   '),
        throwsArgumentError,
      );
    });
  });

  group('source audit', () {
    test('the OpenRouter client never reads the key vault', () {
      final String root = _repoRoot() ?? '';
      final List<String> code =
          File('$root/lib/features/ai/key/openrouter_client.dart')
              .readAsLinesSync()
              .where((String line) => !line.trimLeft().startsWith('//'))
              .toList();
      final String body = code.join('\n');
      expect(body.contains('byok_vault'), isFalse);
      expect(body.contains('ByokVault'), isFalse);
      expect(body.contains('readKey'), isFalse);
    });

    test('no logging call exists in the AI feature', () {
      final List<String> offenders = <String>[];
      for (final File file in _dartFiles('lib/features/ai')) {
        final List<String> lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final String line = lines[i].trim();
          if (line.startsWith('//')) continue;
          if (RegExp(r'\b(print|debugPrint|developer\.log)\s*\(')
              .hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('no provider key literal is committed', () {
      final RegExp literal = RegExp(r'sk-or-v1-[A-Za-z0-9]{16,}');
      final List<String> offenders = <String>[];
      for (final File file in _dartFiles('lib')) {
        if (literal.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('booking code has no dependency on the AI feature', () {
      final List<String> offenders = <String>[];
      for (final String dir in <String>[
        'lib/features/booking',
        'lib/features/bookings',
      ]) {
        for (final File file in _dartFiles(dir)) {
          final String source = file.readAsStringSync();
          if (source.contains('features/ai/') ||
              source.contains('OpenRouterClient') ||
              source.contains('RewriteState')) {
            offenders.add(file.path);
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
