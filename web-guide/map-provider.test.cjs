// Tests for the optional Google Maps provider layer (P41).
//
// Run: node --test web-guide/map-provider.test.cjs
//
// These tests cover provider SELECTION and the fallback decision only. They do
// not, and cannot, prove that a Google map renders: that needs an owner key,
// billing and device verification (see docs/owner/maps-setup.md).

const test = require('node:test');
const assert = require('node:assert/strict');

const provider = require('./map-provider.js');

function fakeDocument() {
  const appended = [];
  const head = {
    appendChild(script) {
      appended.push(script);
      return script;
    },
  };
  return {
    appended,
    createElement() {
      return {};
    },
    head,
  };
}

test('no configuration keeps the proven OpenStreetMap renderer', () => {
  assert.equal(provider.resolveProvider(undefined).provider, provider.OSM);
  assert.equal(provider.resolveProvider({}).provider, provider.OSM);
  assert.equal(provider.resolveProvider(null).reason, 'no_google_maps_key');
});

test('an empty or whitespace key never activates Google Maps', () => {
  assert.equal(
    provider.resolveProvider({ googleMapsApiKey: '   ' }).provider,
    provider.OSM,
  );
  assert.equal(
    provider.resolveProvider({ googleMapsApiKey: '' }).reason,
    'no_google_maps_key',
  );
});

test('a malformed key is rejected instead of being sent to Google', () => {
  const resolved = provider.resolveProvider({ googleMapsApiKey: 'short' });
  assert.equal(resolved.provider, provider.OSM);
  assert.equal(resolved.reason, 'invalid_google_maps_key');
  assert.equal(resolved.key, '');
});

test('a well formed owner key selects Google Maps', () => {
  const key = 'AIzaSyD-EXAMPLE_Key_1234567890abcd';
  const resolved = provider.resolveProvider({ googleMapsApiKey: key });
  assert.equal(resolved.provider, provider.GOOGLE);
  assert.equal(resolved.key, key);
  assert.equal(resolved.reason, 'google_maps_key_present');
});

test('the Google script URL is https, key encoded and never an iframe', () => {
  const url = provider.googleMapsScriptUrl('AIzaSyD-EXAMPLE_Key_1234567890abcd');
  assert.match(url, /^https:\/\/maps\.googleapis\.com\/maps\/api\/js\?/);
  assert.match(url, /key=AIzaSyD-EXAMPLE_Key_1234567890abcd/);
  assert.doesNotMatch(url, /iframe|embed/i);
});

test('an invalid key cannot build a script URL at all', () => {
  assert.throws(() => provider.googleMapsScriptUrl('x'), /invalid Google Maps key/);
});

test('a Google script error falls back to OpenStreetMap', async () => {
  const doc = fakeDocument();
  const loadedPromise = provider.loadGoogleMaps(doc, 'AIzaSyD-EXAMPLE_Key_1234567890abcd', {
    timeoutMs: 200,
  });
  assert.equal(doc.appended.length, 1);
  doc.appended[0].onerror();
  assert.equal(await loadedPromise, false);
});

test('a Google script that never reports back times out to the fallback', async () => {
  const doc = fakeDocument();
  const started = Date.now();
  const loaded = await provider.loadGoogleMaps(doc, 'AIzaSyD-EXAMPLE_Key_1234567890abcd', {
    timeoutMs: 50,
  });
  assert.equal(loaded, false);
  assert.ok(Date.now() - started >= 40, 'waited for the timeout');
});

test('a Google script that loads with the API present is accepted', async () => {
  globalThis.google = { maps: {} };
  try {
    const doc = fakeDocument();
    const loadedPromise = provider.loadGoogleMaps(
      doc,
      'AIzaSyD-EXAMPLE_Key_1234567890abcd',
      { timeoutMs: 500 },
    );
    doc.appended[0].onload();
    assert.equal(await loadedPromise, true);
  } finally {
    delete globalThis.google;
  }
});

test('a script load without the API still falls back', async () => {
  delete globalThis.google;
  const doc = fakeDocument();
  const loadedPromise = provider.loadGoogleMaps(
    doc,
    'AIzaSyD-EXAMPLE_Key_1234567890abcd',
    { timeoutMs: 500 },
  );
  doc.appended[0].onload();
  assert.equal(await loadedPromise, false);
});

test('a missing document degrades to the fallback instead of throwing', async () => {
  assert.equal(
    await provider.loadGoogleMaps(null, 'AIzaSyD-EXAMPLE_Key_1234567890abcd'),
    false,
  );
});
