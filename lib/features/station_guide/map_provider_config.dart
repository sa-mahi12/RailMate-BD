/// F15/P41: map provider configuration handed to the bundled guide page.
///
/// The proven renderer is Leaflet + OpenStreetMap. Google Maps stays optional
/// and can only be enabled by a build-time key:
///
///   flutter build apk --dart-define=GOOGLE_MAPS_KEY=...
///
/// Nothing is hardcoded, no key is committed, and an absent key means the page
/// never receives a configuration object (so it keeps using OSM). A Google
/// Maps browser key is public by design, but it still must come from the
/// owner's build environment, not from source.
library;

class GuideMapConfig {
  /// Empty unless the build supplied `--dart-define=GOOGLE_MAPS_KEY=...`.
  static const String googleMapsKey = String.fromEnvironment('GOOGLE_MAPS_KEY');

  static bool get hasGoogleMapsKey => googleMapsKey.trim().isNotEmpty;

  /// JavaScript run after the page loads, or an empty string when unconfigured.
  ///
  /// The config is injected (rather than baked into the asset) so the bundled
  /// page holds no key and the OSM path needs no change.
  static String configScript({String? key}) {
    final String value = (key ?? googleMapsKey).trim();
    if (value.isEmpty) return '';
    final String escaped = escapeForJsLiteral(value);
    return "window.RAILMATE_WEB_CONFIG = { googleMapsApiKey: '$escaped' };"
        ' if (window.RailMateGuide && window.RailMateGuide.refreshMap) {'
        ' window.RailMateGuide.refreshMap(); }';
  }

  /// Single-quoted JS string escaping: backslashes, quotes, and line breaks.
  static String escapeForJsLiteral(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\r', '')
        .replaceAll('\n', '');
  }
}
