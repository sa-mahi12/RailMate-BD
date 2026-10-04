import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/station_guide/station_guide.dart';

/// V4 P12 follow-up: the offline guide catalog covers every live backend
/// station code exactly once (P12: 24 stations), with the stale P22 draft
/// codes corrected (RNG→RGP, TKG→TNG, BSR→CXB).
void main() {
  const liveCodes = <String>{
    'DAC',
    'AIR',
    'JOY',
    'TNG',
    'MYM',
    'JAM',
    'AKH',
    'BRA',
    'CML',
    'FEN',
    'CGP',
    'CXB',
    'SYL',
    'SRM',
    'RJH',
    'ISD',
    'KHL',
    'JSR',
    'BOG',
    'RGP',
    'SDP',
    'PBT',
    'DIN',
    'NOA',
  };

  test('catalog covers all 24 live station codes exactly once', () {
    final codes = stationGuideCatalog.map((g) => g.stationCode).toList();
    expect(codes.toSet(), liveCodes);
    expect(codes.length, liveCodes.length);
    // B09 contract: the original four stay first, in order.
    expect(codes.sublist(0, 4), ['DAC', 'CGP', 'SYL', 'RJH']);
  });

  test('stale draft codes are gone', () {
    expect(findGuideByCode('BSR'), isNull);
    expect(findGuideByCode('RNG'), isNull);
    expect(findGuideByCode('TKG'), isNull);
    expect(findGuideByCode('RGP')?.stationName, 'Rangpur');
    expect(findGuideByCode('TNG')?.stationName, 'Tangail');
    expect(findGuideByCode('CXB')?.stationName, "Cox's Bazar");
  });

  test('only the 8 mapped stations carry coordinates (honest map gap)', () {
    const mapped = {'DAC', 'CGP', 'SYL', 'RJH', 'AIR', 'CML', 'FEN', 'KHL'};
    for (final guide in stationGuideCatalog) {
      if (mapped.contains(guide.stationCode)) {
        expect(
          guide.hasMapPage,
          isTrue,
          reason: '${guide.stationCode} should keep its pin',
        );
      } else {
        expect(
          guide.hasMapPage,
          isFalse,
          reason: '${guide.stationCode} must not point at another pin',
        );
        expect(hasGuideMapPage(guide.stationCode), isFalse);
      }
    }
  });

  test('every entry keeps demo honesty markers, no helpline invented', () {
    // The B09 originals keep their verbatim labeled demo helpline; every
    // newer entry must carry null instead of inventing a number.
    const b09 = {'DAC', 'CGP', 'SYL', 'RJH'};
    for (final guide in stationGuideCatalog) {
      if (b09.contains(guide.stationCode)) {
        expect(guide.helpline, contains('DEMONSTRATION ONLY'));
      } else {
        expect(
          guide.helpline,
          isNull,
          reason: '${guide.stationCode} must not invent a helpline',
        );
      }
      expect(guide.howToReach, contains('DEMONSTRATION ONLY'));
      expect(guide.arrivalTip, contains('DEMONSTRATION ONLY'));
      expect(guide.facilities, isNotEmpty);
    }
  });
}
