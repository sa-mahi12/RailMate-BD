import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/station_guide/station_guide.dart';

/// F15 hermetic tests (Worker D).
///
/// What these tests PROVE: pure-Dart wiring (station-code normalization,
/// query builder, coordinate table) plus static file markers showing the
/// bundled page genuinely includes SASS-compiled styling, GSAP, Leaflet and
/// an external HTML5 video player, and that the Flutter WebView screen
/// degrades offline.
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
        'map re-render keeps the Leaflet instance instead of blanking it',
        () {
          // The Flutter screen injects window.RailMateGuide.showStation(code)
          // after the asset loads, so renderMap() runs twice. Clearing the
          // container while reusing the existing instance deleted Leaflet's own
          // DOM and left an empty grey box with no tiles and no zoom controls.
          final clear = js.indexOf("el.textContent = ''");
          final init = js.indexOf('if (map === null) {');
          expect(clear, greaterThan(0), reason: 'container is still cleared');
          expect(init, greaterThan(0));
          expect(
            clear,
            greaterThan(init),
            reason: 'the container may only be cleared while initialising',
          );
          expect(
            js.split("el.textContent = ''").length - 1,
            1,
            reason: 'exactly one clear site, inside the init branch',
          );
          // Defensive rebuild if the panes were torn down, and repeated
          // invalidateSize for WebView layout that settles late.
          expect(js, contains("el.querySelector('.leaflet-pane')"));
          expect(js, contains('map.remove()'));
          expect(js, contains('[300, 1200]'));
          expect(js, contains('invalidateSize'));
        },
      );

      test(
        'HTML ships a playable bundled video, never the retired YouTube mode',
        () {
          // A YouTube iframe is genuinely embeddable but the player rejects the
          // app's file:///android_asset origin with "Error 153" (no Referer).
          // Streaming the Commons file is not dependable either: Wikimedia
          // answered the WebView with HTTP 403 + text/html, which Chromium
          // blocks as net::ERR_BLOCKED_BY_ORB. The page therefore plays a
          // licensed Commons clip bundled with the app; this guard keeps it so.
          expect(html, contains('<video'));
          expect(html, isNot(contains('listType')));
          expect(html, isNot(contains('http://')));
          expect(html, contains('controls'));
          // Muted autoplay is what the WebView media policy allows without a
          // gesture, and it makes the demo show real motion; sound still needs
          // an explicit unmute.
          expect(html, contains('autoplay'));
          expect(html, contains('muted'));
          // A CORS-mode media fetch (crossorigin=anonymous) fails from the
          // app's file:// origin even though the host sends ACAO:*: the poster
          // and the clip both stayed black in the emulator until it was
          // removed, so the guard keeps it out.
          expect(html, isNot(contains('crossorigin')));
          expect(html, contains('type="video/webm"'));
          // Bundled, not streamed: no remote media host may sneak back in.
          expect(html, isNot(contains('upload.wikimedia.org')));
          final RegExpMatch? src = RegExp(
            r'<source\s+src="(media/[^"]+\.webm)"',
          ).firstMatch(html);
          expect(
            src,
            isNotNull,
            reason: 'the clip must be a bundled asset path',
          );
          final RegExpMatch? poster = RegExp(r'poster="(media/[^"]+\.jpg)"')
              .firstMatch(html);
          expect(poster, isNotNull, reason: 'the poster must be bundled too');
          expect(html, contains('CC BY-SA 4.0'));
          expect(html, contains('Wikimedia Commons'));
          expect(html, contains('DEMONSTRATION ONLY'));
          expect(html, isNot(contains('R-09 BLOCKED')));
          expect(html, isNot(contains('R-10 BLOCKED')));
          expect(html, isNot(contains('R-16 BLOCKED')));

          // The files must really be in the checkout and of sane size, so a
          // placeholder or a truncated download cannot pass this test.
          for (final String name in <String>[
            src!.group(1)!,
            poster!.group(1)!,
          ]) {
            final File asset = File('$root/web-guide/$name');
            expect(asset.existsSync(), isTrue, reason: 'missing $name');
            expect(asset.lengthSync(), greaterThan(10000), reason: name);
          }
          final File clip = File('$root/web-guide/${src.group(1)!}');
          expect(clip.lengthSync(), greaterThan(2000000));
          // Keep the APK honest: the clip stays well under 8 MB.
          expect(clip.lengthSync(), lessThan(8000000));
        },
      );

      test('video ships an in-page play control the WebView can honour', () {
        // Autoplay is best-effort only: the Android WebView ignored muted
        // autoplay and taps on the native media overlay inside this Flutter
        // platform view (emulator, v1.0.0+19/+20, clip stayed at 0:00 and no
        // codec was ever opened). The page therefore ships its own DOM
        // button; a DOM click is a real user activation, so its handler can
        // call video.play(). It sits BELOW the player on purpose - the WebView
        // draws the video in its own surface above DOM content, so an overlay
        // would be invisible.
        expect(html, contains('id="rail-video-play"'));
        expect(html, contains('class="video-play"'));
        final int wrapStart = html.indexOf('<div class="video-wrap">');
        final int wrapEnd = html.indexOf('</div>', wrapStart);
        expect(wrapStart, greaterThanOrEqualTo(0));
        expect(wrapEnd, greaterThan(wrapStart));
        expect(
          html.substring(wrapStart, wrapEnd),
          isNot(contains('rail-video-play')),
          reason: 'the play button must live outside the video surface',
        );
        expect(js, contains("getElementById('rail-video-play')"));
        expect(js, contains('.play()'));
        expect(js, contains('.pause()'));
        expect(js, contains("addEventListener('click'"));
        expect(js, contains("addEventListener('playing'"));
        expect(js, contains("addEventListener('pause'"));
        expect(js, contains('Pause video'));
        // A media element that failed its first resource fetch sits in
        // NETWORK_NO_SOURCE and ignores play(); it needs load() again.
        expect(js, contains('video.load()'));
        expect(js, contains('NETWORK_NO_SOURCE'));
        // paused === false does not mean playing: a source-less element stays
        // "not paused" with currentTime 0, so the toggle must use real state.
        expect(js, contains('function isPlaying()'));
        // A tap must never be a silent no-op: the emulator spent the automatic
        // reload budget before any gesture, after which every tap called
        // play() on NETWORK_NO_SOURCE and nothing happened. A trusted tap
        // resets the budget and forces a fresh load().
        expect(js, contains('MAX_AUTO_RELOADS'));
        expect(js, contains('function ensureSource(force)'));
        expect(js, contains('autoReloads = 0;'));
        expect(js, contains('attemptPlay(true)'));
        expect(js, contains('attemptPlay(false)'));
        expect(css, contains('.video-play'));
      });

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
