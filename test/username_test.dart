import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/username/username.dart';

void main() {
  test('normalize trims and lowercases', () {
    expect(normalizeUsername('  Foo_Bar9 '), equals('foo_bar9'));
  });
  test('rejects invalid: short, long, digit-start, uppercase residue, dash, bangla', () {
    expect(isValidUsername('ab'), isFalse);
    expect(isValidUsername('a' * 21), isFalse);
    expect(isValidUsername('1abc'), isFalse);
    expect(isValidUsername('Foo'), isFalse);
    expect(isValidUsername('foo-bar'), isFalse);
    expect(isValidUsername('ab!'), isFalse);
  });
  test('accepts valid 3-20 letter-start names', () {
    expect(isValidUsername('foo'), isTrue);
    expect(isValidUsername('f00_bar_baz_123456'), isTrue); // 18 chars
    expect(validateUsername(' Foo_1 '), isNull);
  });
  test('validateUsername messages on empty/invalid', () {
    expect(validateUsername('  '), isNotNull);
    expect(validateUsername('1abc'), isNotNull);
  });
}
