// RailMate BD — Station Guide page wiring (F15).
//
// Real implementation: one parameterized page serves all demo stations.
// Static demonstration coordinates only — no live GPS, no geolocation API.
// - Station data mirrors the Flutter demo seeds (DAC/CGP/SYL/RJH) plus the
//   four extra F15 demo stops (AIR/CML/FEN/KHL) with brief-provided coords.
// - Leaflet (CDN) renders the map when reachable; otherwise a genuine
//   offline note is shown instead of a faked map.
// - GSAP (CDN) animates `.card` entrance when reachable; otherwise content
//   renders statically with no animation claims.

(function () {
  'use strict';

  // Static demonstration coordinates (decimal degrees). NOT live GPS.
  var STATIONS = {
    DAC: { code: 'DAC', name: 'Dhaka', lat: 23.8103, lng: 90.4125 },
    CGP: { code: 'CGP', name: 'Chattogram', lat: 22.3569, lng: 91.7832 },
    SYL: { code: 'SYL', name: 'Sylhet', lat: 24.8949, lng: 91.8692 },
    RJH: { code: 'RJH', name: 'Rajshahi', lat: 24.3745, lng: 88.6042 },
    AIR: { code: 'AIR', name: 'Airport (Dhaka)', lat: 23.8431, lng: 90.3973 },
    CML: { code: 'CML', name: 'Cumilla', lat: 23.4607, lng: 91.1809 },
    FEN: { code: 'FEN', name: 'Feni', lat: 23.0235, lng: 91.3841 },
    KHL: { code: 'KHL', name: 'Khulna', lat: 22.8456, lng: 89.5403 }
  };

  var FACILITIES = {
    DAC: ['Waiting Room', 'Ticket Counters', 'Food Stalls'],
    CGP: ['Waiting Room', 'Luggage Counter', 'Tea Stalls'],
    SYL: ['Waiting Room', 'Ticket Counters', 'Restrooms'],
    RJH: ['Waiting Room', 'Food Stalls', 'Restrooms'],
    AIR: ['Waiting Room', 'Ticket Counters'],
    CML: ['Waiting Room', 'Food Stalls'],
    FEN: ['Waiting Room', 'Tea Stalls'],
    KHL: ['Waiting Room', 'Luggage Counter']
  };

  var DEFAULT_CODE = 'DAC';
  var currentCode = DEFAULT_CODE;
  var map = null;
  var marker = null;

  function normalizeCode(raw) {
    var code = String(raw == null ? '' : raw).trim().toUpperCase();
    return Object.prototype.hasOwnProperty.call(STATIONS, code) ? code : DEFAULT_CODE;
  }

  function codeFromQuery() {
    try {
      var params = new URLSearchParams(window.location.search);
      return normalizeCode(params.get('station'));
    } catch (err) {
      return DEFAULT_CODE;
    }
  }

  function renderStation(code) {
    var station = STATIONS[code];
    var title = document.getElementById('station-title');
    if (title) title.textContent = station.name + ' (' + station.code + ') — Guide';

    var overview = document.getElementById('overview-text');
    if (overview) {
      overview.textContent =
        station.name + ' (' + station.code + ') demo guide. DEMONSTRATION ONLY — ' +
        'static sample data, no live departures.';
    }

    var chips = document.getElementById('facility-chips');
    if (chips) {
      chips.innerHTML = '';
      (FACILITIES[code] || []).forEach(function (facility) {
        var li = document.createElement('li');
        li.textContent = station.code + ' — ' + facility;
        chips.appendChild(li);
      });
    }

    var quick = document.getElementById('quick-text');
    if (quick) {
      quick.textContent =
        'Demo helpline 0000 (DEMONSTRATION ONLY). Static coordinates: ' +
        station.lat.toFixed(4) + ', ' + station.lng.toFixed(4) + ' — not live GPS.';
    }

    var note = document.getElementById('coords-note');
    if (note) {
      note.textContent =
        'Static demonstration coordinates: ' + station.lat.toFixed(4) + ', ' +
        station.lng.toFixed(4) + '. Not live GPS. Map tiles © OpenStreetMap contributors.';
    }

    var picker = document.getElementById('station-picker');
    if (picker) {
      var buttons = picker.querySelectorAll('button');
      for (var i = 0; i < buttons.length; i++) {
        buttons[i].setAttribute(
          'aria-pressed',
          buttons[i].getAttribute('data-code') === code ? 'true' : 'false'
        );
      }
    }
  }

  function renderMap(code) {
    var station = STATIONS[code];
    var el = document.getElementById('map');
    var fallback = document.getElementById('map-fallback');
    if (!el) return;
    if (typeof L === 'undefined') {
      // Leaflet CDN unreachable (offline): genuine fallback, no faked map.
      el.classList.add('map-unavailable');
      el.textContent =
        'Offline — interactive map unavailable. ' + station.name +
        ' demo coordinates: ' + station.lat.toFixed(4) + ', ' +
        station.lng.toFixed(4) + '.';
      if (fallback) fallback.hidden = false;
      return;
    }
    if (fallback) fallback.hidden = true;
    el.classList.remove('map-unavailable');
    // Leaflet owns everything inside the container once initialised, so the
    // container is cleared only on (re)initialisation. Clearing it while
    // reusing the old instance left an empty box with no controls: the
    // Flutter screen calls showStation() after load, so a second render used
    // to wipe the map Leaflet had just built.
    if (map !== null && !el.querySelector('.leaflet-pane')) {
      // Container was torn down behind our back - rebuild instead of blanking.
      try { map.remove(); } catch (err) { /* instance already detached */ }
      map = null;
      marker = null;
    }
    if (map === null) {
      el.textContent = '';
      map = L.map('map', { scrollWheelZoom: false }).setView([station.lat, station.lng], 13);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
      }).addTo(map);
      marker = L.marker([station.lat, station.lng]).addTo(map);
    } else {
      map.setView([station.lat, station.lng], 13);
      marker.setLatLng([station.lat, station.lng]);
    }
    marker.bindPopup('<b>' + station.name + ' (' + station.code + ')</b><br>DEMONSTRATION ONLY').openPopup();
    // The WebView can report its final layout after Leaflet measured the box.
    [300, 1200].forEach(function (delay) {
      setTimeout(function () { if (map) map.invalidateSize(); }, delay);
    });
  }

  function animateEntrance() {
    if (typeof gsap === 'undefined') return; // static fallback, no fake claim
    try {
      gsap.from('.card', { y: 24, opacity: 0, duration: 0.6, stagger: 0.08, ease: 'power2.out', clearProps: 'all' });
    } catch (err) {
      /* static content remains - animation is enhancement only */
    }
  }

  // F15 video: muted autoplay is attempted first (allowed where the WebView
  // permits it) and the page's own button is the guaranteed path - a DOM click
  // is a real user activation, so play() is honoured even when the platform
  // blocks autoplay. The button doubles as pause and always reflects the real
  // element state: it is never hidden while the clip is stalled at 0:00.
  //
  // The emulator proved the real failure was source recovery, not policy: the
  // element sat in NETWORK_NO_SOURCE (networkState 3, readyState 0, error
  // null) after its first fetch, play() alone never opens a codec, and load()
  // revived it (CDP: load() + play() reached readyState 4 and played). The
  // bundled clip removes the network from that path, but the same recovery
  // still applies, and a tap must never be a silent dead end.
  function initVideo() {
    var video = document.getElementById('rail-video');
    var button = document.getElementById('rail-video-play');
    if (!video || !button) return;

    var NO_SOURCE = 3; // HTMLMediaElement.NETWORK_NO_SOURCE
    // Recovery budget for automatic attempts only (page load, error event).
    // A real tap is never budgeted - see the click handler.
    var autoReloads = 0;
    var MAX_AUTO_RELOADS = 2;

    // paused === false only means "a play request is pending"; on a source-less
    // element it stays false while nothing plays (CDP: paused=false with
    // readyState 0, networkState 3). Every decision uses real playback state.
    function isPlaying() {
      return !video.paused && !video.ended && video.currentTime > 0;
    }

    function syncButton() {
      var playing = isPlaying();
      button.hidden = false;
      button.textContent = playing ? 'Pause video' : 'Play video';
      button.setAttribute('aria-label', playing ? 'Pause the station guide video' : 'Play the station guide video');
    }

    // A media element whose first resource fetch failed sits in
    // NETWORK_NO_SOURCE (networkState 3, readyState 0) and ignores play()
    // forever; load() re-runs resource selection and revives it. Bounded for
    // automatic callers so a genuinely offline reader never loops; a user tap
    // passes force and always gets a fresh attempt.
    function ensureSource(force) {
      if (video.readyState > 0 && video.networkState !== NO_SOURCE) return;
      if (!force) {
        if (autoReloads >= MAX_AUTO_RELOADS) return;
        autoReloads += 1;
      }
      try {
        video.load();
      } catch (err) {
        /* the button and the offline note still explain the state */
      }
    }

    function attemptPlay(force) {
      ensureSource(force === true);
      try {
        var started = video.play();
        if (started && typeof started.catch === 'function') {
          started.catch(syncButton); // blocked: keep the button, no fake state
        }
      } catch (err) {
        /* keep the control usable */
      }
      // A play() that never produces a frame must not leave the reader without
      // a control; one automatic reload is allowed here, at most twice overall.
      setTimeout(function () {
        if (video.currentTime > 0) {
          syncButton();
          return;
        }
        if (video.networkState === NO_SOURCE) ensureSource(false);
        if (video.paused || video.readyState === 0) {
          var again = video.play();
          if (again && typeof again.catch === 'function') {
            again.catch(syncButton);
          }
        }
        syncButton();
      }, 2500);
    }

    button.addEventListener('click', function () {
      if (isPlaying()) {
        video.pause();
      } else {
        // The emulator showed the dead end this prevents: the automatic
        // attempts ran out while the element was still source-less, so every
        // later tap called play() on NETWORK_NO_SOURCE and did nothing. A tap
        // is a real user activation, so it resets the budget and reloads.
        autoReloads = 0;
        attemptPlay(true);
      }
    });
    video.addEventListener('playing', syncButton);
    video.addEventListener('play', syncButton);
    video.addEventListener('timeupdate', syncButton);
    video.addEventListener('pause', syncButton);
    video.addEventListener('ended', syncButton);
    video.addEventListener('stalled', syncButton);
    video.addEventListener('error', function () {
      ensureSource(false);
      syncButton();
    });

    // Best effort only: if the WebView refuses, the button stays usable.
    video.muted = true;
    attemptPlay(false);
    syncButton();
  }

  function showStation(raw) {
    currentCode = normalizeCode(raw);
    renderStation(currentCode);
    renderMap(currentCode);
  }

  function buildPicker() {
    var picker = document.getElementById('station-picker');
    if (!picker) return;
    Object.keys(STATIONS).forEach(function (code) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = code;
      btn.setAttribute('data-code', code);
      btn.setAttribute('aria-pressed', code === currentCode ? 'true' : 'false');
      btn.addEventListener('click', function () { showStation(code); });
      picker.appendChild(btn);
    });
  }

  function init() {
    currentCode = codeFromQuery();
    buildPicker();
    renderStation(currentCode);
    renderMap(currentCode);
    animateEntrance();
    initVideo();
    document.body.setAttribute('data-guide-ready', 'true');
  }

  // Public hook used by the Flutter WebView after asset load.
  window.RailMateGuide = { showStation: showStation, stationCodes: Object.keys(STATIONS) };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
