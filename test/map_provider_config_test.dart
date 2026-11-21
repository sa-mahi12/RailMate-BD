import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:railmate_bd/features/station_guide/map_provider_config.dart';

/// P41 map-provider tests.
///
/// What they prove: the app only sends a provider configuration when a build
/// supplied a key, the injected JavaScript is escaped, and no key is committed
/// into the bundled guide assets. What they do NOT prove: that Google Maps
/// renders — that needs an owner key, billing and device verification
/// (docs/owner/maps-setup.md).
String? _repoRoot() {
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
  group('GuideMapConfig', () {
    test('an unconfigured build injects nothing at all', () {
      expect(GuideMapConfig.configScript(key: ''), isEmpty);
      expect(GuideMapConfig.configScript(key: '   '), isEmpty);
    });

    test('a configured key creates the provider config and a redraw', () {
      final String script = GuideMapConfig.configScript(
        key: 'AIzaSyD-EXAMPLE_Key_1234567890abcd',
      );
      expect(script, contains('window.RAILMATE_WEB_CONFIG'));
      expect(script, contains('googleMapsApiKey'));
      expect(script, contains('refreshMap'));
      expect(script, contains('AIzaSyD-EXAMPLE_Key_1234567890abcd'));
    });

    test(
      'quotes, backslashes and newlines cannot break out of the literal',
      () {
        final String script = GuideMapConfig.configScript(key: "ab'c\\d\ne");
        expect(script, contains(r"ab\'c\\d"));
        expect(script.contains("'ab'c"), isFalse);
        expect(script.contains('\n'), isFalse);
      },
    );
  });

  group('committed assets', () {
    test('no Google Maps key is baked into the bundled guide', () {
      final String root = _repoRoot() ?? '';
      expect(root, isNotEmpty, reason: 'repo root discoverable');
      final RegExp keyLike = RegExp(r'AIza[0-9A-Za-z_\-]{30,}');
      final List<String> offenders = <String>[];
      // Only the files that actually ship inside the APK bundle.
      const List<String> shipped = <String>[
        'index.html',
        'guide.js',
        'guide.scss',
        'styles.css',
        'map-provider.js',
      ];
      for (final String name in shipped) {
        final File file = File('$root/web-guide/$name');
        if (!file.existsSync()) continue;
        if (keyLike.hasMatch(file.readAsStringSync())) {
          offenders.add(name);
        }
      }
      expect(offenders, isEmpty);
    });

    test('the guide page loads the provider module before guide.js', () {
      final String root = _repoRoot() ?? '';
      final String html = File('$root/web-guide/index.html').readAsStringSync();
      final int provider = html.indexOf('map-provider.js');
      final int guide = html.indexOf('src="guide.js"');
      expect(provider, greaterThan(0), reason: 'provider script shipped');
      expect(guide, greaterThan(provider), reason: 'loaded before guide.js');
      expect(html.contains('AIza'), isFalse);
    });

    test('the provider module never builds an iframe embed', () {
      final String root = _repoRoot() ?? '';
      final String source = File('$root/web-guide/map-provider.js')
          .readAsStringSync();
      expect(source.contains('<iframe'), isFalse);
      expect(source.contains('iframe src'), isFalse);
      expect(source.contains('googleMapsApiKey'), isTrue);
    });
  });
}
