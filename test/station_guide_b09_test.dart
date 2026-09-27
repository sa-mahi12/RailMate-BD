import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/station_guide/station_guide.dart';

void main() {
  test('findGuideByCode returns the seeded guide for each known code', () {
    for (final code in ['DAC', 'CGP', 'SYL', 'RJH']) {
      final guide = findGuideByCode(code);
      expect(guide, isNotNull);
      expect(guide!.stationCode, code);
    }
    expect(findGuideByCode('dac')?.stationName, 'Dhaka');
    expect(findGuideByCode('  cgp ')?.stationName, 'Chattogram');
    expect(demoStationGuides.length, 4);
  });

  test('findGuideByCode returns null for unknown or blank codes', () {
    expect(findGuideByCode('XXX'), isNull);
    expect(findGuideByCode(''), isNull);
    expect(findGuideByCode('   '), isNull);
  });

  test('web-guide scaffold has placeholder markers and no live embeds', () {
    final html = File('web-guide/index.html').readAsStringSync();
    expect(html, contains('data-embed-pending="google-maps"'));
    expect(html, contains('data-embed-pending="youtube"'));
    expect(html, contains('R-09 BLOCKED'));
    expect(html, contains('R-10 BLOCKED'));
    expect(html, contains('R-15 BLOCKED'));
    expect(html, contains('R-16 BLOCKED'));
    expect(html, isNot(contains('<iframe')));
    expect(html, isNot(contains('https://')));
  });
}
