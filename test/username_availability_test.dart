import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/auth/username/username_availability.dart';

void main() {
  test('invalid format never queries', () async {
    var called = false;
    final c = UsernameAvailabilityChecker(
      existsQuery: (n) async {
        called = true;
        return true;
      },
    );
    expect(await c.check('1bad'), equals(UsernameAvailability.invalid));
    expect(called, isFalse);
  });
  test('taken vs available', () async {
    final c = UsernameAvailabilityChecker(
      existsQuery: (n) async => n == 'taken_name',
    );
    expect(
      await c.check('Taken_Name'),
      equals(UsernameAvailability.taken),
    ); // normalization
    expect(await c.check('free_name'), equals(UsernameAvailability.available));
  });
  test('query throw maps to error', () async {
    final c = UsernameAvailabilityChecker(
      existsQuery: (_) async => throw Exception('net'),
    );
    expect(await c.check('ok_name'), equals(UsernameAvailability.error));
  });
}
