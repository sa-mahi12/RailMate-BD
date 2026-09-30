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

  test('web-guide page carries real interactive embeds (F15)', () {
    // F15 retired the B09 BLOCKED scaffold: the page now genuinely includes
    // Leaflet map, GSAP animation and a YouTube embed with honest
    // offline/no-network degradation (asserted in test/guide_f15_test.dart).
    // This legacy case pins the new reality so a silent revert to the
    // placeholder scaffold fails loudly.
    final html = File('web-guide/index.html').readAsStringSync();
    expect(html, contains('<iframe'));
    expect(html, contains('leaflet'));
    expect(html, contains('gsap'));
    expect(html, isNot(contains('data-embed-pending="google-maps"')));
    expect(html, isNot(contains('R-10 BLOCKED')));
  });
}
