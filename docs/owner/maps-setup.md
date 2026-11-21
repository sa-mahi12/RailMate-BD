# Station map — provider decision and optional Google Maps setup (P41 / R-10)

## Current, device-proven implementation

* Bundled page `web-guide/index.html` + `web-guide/guide.js` in an Android
  WebView.
* **Leaflet 1.9.4** + **OpenStreetMap** tiles, interactive marker, station
  picker (8 demo stations) and honest offline text when the CDN is unreachable.
* The blank-map defect (Leaflet instance torn down on the second render) was
  fixed in `6e3ce42` and verified on the `v1.0.0+26` release on the emulator.

## Requirement status

The original teacher text mentioned "Google Maps / iframe"; the later six-item
announcement did not repeat the provider name. The requirement therefore stays
recorded as a **documented deviation** (R-10), not PASS:

* the delivered map is genuinely interactive (pan/zoom/marker/station switch),
* it is **not** a Google Maps embed, and
* no live Google Maps claim is made anywhere.

## Optional Google Maps path (owner decision)

P41 added a provider-selection layer that can activate Google Maps **only** when
a key is supplied at build time. Without a key nothing changes and no Google
script is loaded.

### If the owner decides OSM is acceptable

Nothing to do. Keep R-10 as a deviation, attach this document to the submission
and tell the teacher the map is interactive OpenStreetMap.

### If the owner decides Google Maps is mandatory

1. Google Cloud Console → create/select a project → enable
   **Maps JavaScript API** → billing must be active (the API is not free).
2. Credentials → **Create credentials → API key**.
3. Restrict the key: **Application restrictions → Android apps**, add the
   release package name (`com.example.railmate_bd` — check
   `android/app/build.gradle` for the exact `applicationId`) and the release
   signing SHA-1. Optionally restrict the API to Maps JavaScript API.
   A Maps JavaScript key used from a WebView is visible to the device by
   design; the restriction is what protects it.
4. Build with the key from the environment, never from source:

   ```bash
   flutter build apk --release \
     --dart-define=GOOGLE_MAPS_KEY="$(cat gmaps-key.txt)" \
     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```

   `GOOGLE_MAPS_KEY` is read by `lib/features/station_guide/map_provider_config.dart`
   and injected into the WebView after load; the bundled assets never contain it.
5. Device verification (required before any PASS claim):
   * open a station guide, confirm the map shows Google tiles/attribution,
   * switch stations (marker moves, no blank box),
   * airplane mode: the page must show its honest offline note, never a blank
     frame,
   * remove the key and rebuild: OSM must return with no Google request.

### Runtime behaviour and failure modes

| Situation | Behaviour |
|---|---|
| No key at build time | `window.RAILMATE_WEB_CONFIG` is never set; Leaflet/OSM renders exactly as today |
| Key present, script loads | Google map renders; Leaflet path untouched |
| Key present, script blocked/timeout (8 s) | `googleFailed = true`, OSM renderer used; no empty box |
| Key present, `google.maps` throws | caught, falls back to OSM |
| Invalid/blank key in config | treated as absent (`invalid_google_maps_key` / `no_google_maps_key`) |

### Tests that exist

* `node --test web-guide/map-provider.test.cjs` — provider selection, missing
  configuration, malformed key, script error/timeout fallback, no iframe.
* `flutter test test/map_provider_config_test.dart` — injection only with a
  key, JS escaping, no committed key in the bundled assets.

These tests do **not** prove Google rendering. That needs a key, billing and a
device run, which is why R-10 remains a deviation until the owner decides.
