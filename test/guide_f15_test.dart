import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/station_guide/station_guide.dart';

/// F15 hermetic tests (Worker D).
///
/// What these tests PROVE: pure-Dart wiring (station-code normalization,
/// query builder, coordinate table) plus static file markers showing the
/// bundled page genuinely includes SASS-compiled styling, GSAP, Leaflet and
/// a YouTube embed, and that the Flutter WebView screen degrades offline.
///
/// What they do NOT prove: actual rendering, animation visibility, map tiles
/// or video playback — that is F21 device proof on a real phone
/// (see the manual checklist in the F15 handoff).
String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/web-guide/index.html').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return null;
}

void main() {
  group('F15 guide station-code builders (pure Dart)', () {
    test('normalizeGuideStationCode passes known codes through', () {
      for (final code in [
        'DAC',
        'CGP',
        'SYL',
        'RJH',
        'AIR',
        'CML',
        'FEN',
        'KHL',
      ]) {
        expect(normalizeGuideStationCode(code), code);
      }
    });

    test('normalizeGuideStationCode is case-insensitive and trims', () {
      expect(normalizeGuideStationCode('dac'), 'DAC');
      expect(normalizeGuideStationCode('  cgp '), 'CGP');
    });

    test('normalizeGuideStationCode falls back to default, never throws', () {
      expect(normalizeGuideStationCode('XXX'), defaultGuideStationCode);
      expect(normalizeGuideStationCode(''), defaultGuideStationCode);
      expect(normalizeGuideStationCode('   '), defaultGuideStationCode);
      expect(defaultGuideStationCode, 'DAC');
    });

    test('guideStationQuery builds the in-page selector', () {
      expect(guideStationQuery('CGP'), '?station=CGP');
      expect(guideStationQuery(' khl '), '?station=KHL');
      expect(guideStationQuery('bogus'), '?station=DAC');
    });

    test(
      'stationCoordinates holds the 8 brief seed values in Bangladesh bounds',
      () {
        const expected = <String, List<double>>{
          'DAC': [23.8103, 90.4125],
          'CGP': [22.3569, 91.7832],
          'SYL': [24.8949, 91.8692],
          'RJH': [24.3745, 88.6042],
          'AIR': [23.8431, 90.3973],
          'CML': [23.4607, 91.1809],
          'FEN': [23.0235, 91.3841],
          'KHL': [22.8456, 89.5403],
        };
        expect(stationCoordinates.keys.toSet(), expected.keys.toSet());
        for (final entry in expected.entries) {
          final actual = stationCoordinates[entry.key]!;
          expect(
            actual[0],
            closeTo(entry.value[0], 0.0001),
            reason: '${entry.key} lat',
          );
          expect(
            actual[1],
            closeTo(entry.value[1], 0.0001),
            reason: '${entry.key} lng',
          );
          expect(actual[0], inInclusiveRange(20.0, 27.0));
          expect(actual[1], inInclusiveRange(88.0, 93.0));
        }
      },
    );

    test('guideAssetPath points at the bundled parameterized page', () {
      expect(guideAssetPath, 'web-guide/index.html');
    });
  });

  group(
    'F15 bundled page markers (static file wiring)',
    () {
      late final String root;
      late final String html;
      late final String js;
      late final String scss;
      late final String css;
      late final String webviewScreen;

      setUpAll(() {
        root = _findRepoRoot()!;
        html = File('$root/web-guide/index.html').readAsStringSync();
        js = File('$root/web-guide/guide.js').readAsStringSync();
        scss = File('$root/web-guide/guide.scss').readAsStringSync();
        css = File('$root/web-guide/styles.css').readAsStringSync();
        webviewScreen = File(
          '$root/lib/features/station_guide/guide_webview_screen.dart',
        ).readAsStringSync();
      });

      test('HTML links SASS-compiled CSS and both sources are committed', () {
        expect(html, contains('href="styles.css"'));
        // Real SCSS source markers (variables, mixin, nesting).
        expect(scss, contains(r'$teal'));
        expect(scss, contains('@mixin card'));
        expect(scss, contains('.guide-header'));
        // Compiled twin: resolved values, no raw SCSS syntax.
        expect(css, contains('#0e5a66'));
        expect(css, isNot(contains(r'$teal')));
        expect(css, isNot(contains('@mixin')));
        expect(css, isNot(contains('@include')));
      });

      test(
        'HTML loads GSAP and Leaflet from CDN with a visible/no-fake contract',
        () {
          expect(html, contains('gsap'));
          expect(html, contains('leaflet'));
          expect(html, contains('https://'));
          // JS guards CDN absence with genuine fallbacks, not faked content.
          expect(js, contains('typeof gsap'));
          expect(js, contains('typeof L'));
          expect(js, contains('Offline'));
          expect(js, isNot(contains('R-15 BLOCKED')));
        },
      );

      test('JS embeds the 8 static station coordinates (no live GPS)', () {
        for (final entry in {
          'DAC': ['23.8103', '90.4125'],
          'CGP': ['22.3569', '91.7832'],
          'SYL': ['24.8949', '91.8692'],
          'RJH': ['24.3745', '88.6042'],
          'AIR': ['23.8431', '90.3973'],
          'CML': ['23.4607', '91.1809'],
          'FEN': ['23.0235', '91.3841'],
          'KHL': ['22.8456', '89.5403'],
        }.entries) {
          expect(js, contains(entry.key), reason: 'missing ${entry.key}');
          for (final coord in entry.value) {
            expect(js, contains(coord), reason: 'missing $coord');
          }
        }
        expect(js, contains('showStation'));
        expect(js, contains('window.RailMateGuide'));
        // No live-GPS API usage: the honest "no geolocation API" comment is
        // allowed, but actual navigator.geolocation calls are not.
        expect(js.toLowerCase(), isNot(contains('navigator.geolocation')));
        expect(js, isNot(contains('getCurrentPosition')));
        expect(js.toLowerCase(), isNot(contains('watchposition')));
      });

      test(
        'HTML contains a real YouTube iframe embed, labelled demonstration',
        () {
          expect(html, contains('<iframe'));
          expect(html, contains('youtube.com/embed'));
          expect(html, contains('DEMONSTRATION ONLY'));
          expect(html, isNot(contains('R-09 BLOCKED')));
          expect(html, isNot(contains('R-10 BLOCKED')));
          expect(html, isNot(contains('R-16 BLOCKED')));
        },
      );

      test('WebView screen loads the bundled asset and degrades offline', () {
        expect(webviewScreen, contains('loadFlutterAsset'));
        expect(webviewScreen, contains('guideAssetPath'));
        expect(webviewScreen, contains('showStation'));
        expect(webviewScreen, contains('onWebResourceError'));
        expect(webviewScreen, contains('Guide unavailable offline'));
        expect(webviewScreen, contains('Retry'));
      });
    },
    skip: _findRepoRoot() == null
        ? 'Repo root (web-guide/index.html) not found from ${Directory.current.path}; '
              'run from the RailMateBD checkout so file-marker tests resolve.'
        : null,
  );
}
