import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/signup_verify.dart';

/// Deep-link contract for `railmatebd://auth/verify`. Pure Dart —
/// no Flutter binding, no network.
void main() {
  Uri link(String raw) => Uri.parse(raw);

  group('isSignupVerifyLink', () {
    test('accepts the verify path with a PKCE code', () {
      expect(
        isSignupVerifyLink(link('railmatebd://auth/verify?code=abc123')),
        isTrue,
      );
    });

    test('accepts the verify path even without a code', () {
      expect(isSignupVerifyLink(link('railmatebd://auth/verify')), isTrue);
    });

    test('rejects wrong scheme, host and path', () {
      expect(
        isSignupVerifyLink(link('https://auth/verify?code=abc123')),
        isFalse,
      );
      expect(
        isSignupVerifyLink(link('railmatebd://other/verify?code=abc123')),
        isFalse,
      );
      expect(
        isSignupVerifyLink(
          link('railmatebd://auth/reset-password?code=abc123'),
        ),
        isFalse,
      );
      expect(isSignupVerifyLink(link('railmatebd://auth/login')), isFalse);
    });
  });

  group('parseSignupVerifyLink', () {
    test('extracts the PKCE code from the query', () {
      final parsed = parseSignupVerifyLink(
        link('railmatebd://auth/verify?code=ABC123&foo=bar'),
      )!;
      expect(parsed.code, 'ABC123');
    });

    test('accepts the code from the fragment as a fallback', () {
      final parsed = parseSignupVerifyLink(
        link('railmatebd://auth/verify#code=FRAG456'),
      )!;
      expect(parsed.code, 'FRAG456');
    });

    test('prefers the query over the fragment', () {
      final parsed = parseSignupVerifyLink(
        link('railmatebd://auth/verify?code=QUERY#code=FRAG'),
      )!;
      expect(parsed.code, 'QUERY');
    });

    test('returns null when the code is missing', () {
      expect(parseSignupVerifyLink(link('railmatebd://auth/verify')), isNull);
      expect(
        parseSignupVerifyLink(link('railmatebd://auth/verify?foo=bar')),
        isNull,
      );
    });

    test('returns null for non-verify links, never throws', () {
      expect(
        parseSignupVerifyLink(
          link('railmatebd://auth/reset-password?code=abc'),
        ),
        isNull,
      );
      expect(
        parseSignupVerifyLink(link('https://example.com/?code=abc')),
        isNull,
      );
    });
  });
}
