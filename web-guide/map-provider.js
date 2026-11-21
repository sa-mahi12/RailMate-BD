// RailMate BD - station map provider selection (F15/P41).
//
// The proven map stays OpenStreetMap + Leaflet. Google Maps is an OPTIONAL
// layer that can only activate when an owner-supplied key is present in
// `window.RAILMATE_WEB_CONFIG.googleMapsApiKey`. Without a key nothing changes:
// there is no Google script, no iframe and no hidden default key.
//
// This module is deliberately pure and injectable so the selection and the
// fallback rules can be tested without a browser or a Google key:
//   node --test web-guide/map-provider.test.cjs
//
// It is loaded both as a classic script (window.RailMateMapProvider) and as a
// CommonJS module (tests).
(function (root, factory) {
  'use strict';
  var api = factory();
  if (typeof module === 'object' && module && module.exports) {
    module.exports = api;
  } else {
    root.RailMateMapProvider = api;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  var GLOBAL = typeof globalThis !== 'undefined' ? globalThis : {};
  var OSM = 'osm';
  var GOOGLE = 'google';
  // Google browser keys are long and use URL-safe characters. A short or
  // malformed value is treated as absent rather than sent to Google.
  var KEY_RE = /^[A-Za-z0-9_-]{20,120}$/;
  var DEFAULT_TIMEOUT_MS = 8000;

  function readKey(config) {
    if (!config || typeof config !== 'object') return '';
    var raw = config.googleMapsApiKey;
    return typeof raw === 'string' ? raw.trim() : '';
  }

  /**
   * Decides which renderer to use.
   * @returns {{provider: string, key: string, reason: string}}
   */
  function resolveProvider(config) {
    var key = readKey(config);
    if (key === '') return { provider: OSM, key: '', reason: 'no_google_maps_key' };
    if (!KEY_RE.test(key)) {
      return { provider: OSM, key: '', reason: 'invalid_google_maps_key' };
    }
    return { provider: GOOGLE, key: key, reason: 'google_maps_key_present' };
  }

  /** Script URL for the Google Maps JS API (never an iframe embed URL). */
  function googleMapsScriptUrl(key) {
    if (!KEY_RE.test(String(key || ''))) {
      throw new Error('invalid Google Maps key');
    }
    return (
      'https://maps.googleapis.com/maps/api/js?v=weekly&key=' +
      encodeURIComponent(key)
    );
  }

  /**
   * Loads the Google Maps JS API. Never rejects: resolves false when the
   * script errors or the timeout passes, so the caller can fall back to OSM
   * instead of leaving an empty box.
   *
   * @param {Document} doc injected for tests
   * @param {string} key
   * @param {{timeoutMs?: number, onLoaded?: Function}} options
   * @returns {Promise<boolean>}
   */
  function loadGoogleMaps(doc, key, options) {
    var opts = options || {};
    var timeoutMs =
      typeof opts.timeoutMs === 'number' && opts.timeoutMs > 0
        ? opts.timeoutMs
        : DEFAULT_TIMEOUT_MS;

    return new Promise(function (resolve) {
      if (!doc || !doc.createElement || !doc.head) {
        resolve(false);
        return;
      }
      var settled = false;
      var timer = null;

      function finish(ok) {
        if (settled) return;
        settled = true;
        if (timer !== null) clearTimeout(timer);
        resolve(ok);
      }

      var script;
      try {
        script = doc.createElement('script');
      } catch (err) {
        finish(false);
        return;
      }
      script.async = true;
      script.src = googleMapsScriptUrl(key);
      script.onload = function () {
        var ok = !!(GLOBAL.google && GLOBAL.google.maps);
        if (ok && typeof opts.onLoaded === 'function') {
          try {
            opts.onLoaded();
          } catch (err) {
            finish(false);
            return;
          }
        }
        finish(ok);
      };
      script.onerror = function () {
        finish(false);
      };

      timer = setTimeout(function () {
        finish(false);
      }, timeoutMs);

      try {
        doc.head.appendChild(script);
      } catch (err) {
        finish(false);
      }
    });
  }

  return {
    OSM: OSM,
    GOOGLE: GOOGLE,
    DEFAULT_TIMEOUT_MS: DEFAULT_TIMEOUT_MS,
    resolveProvider: resolveProvider,
    googleMapsScriptUrl: googleMapsScriptUrl,
    loadGoogleMaps: loadGoogleMaps
  };
});
