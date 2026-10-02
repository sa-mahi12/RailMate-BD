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
    el.textContent = '';
    if (map === null) {
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
    // Fix sizing when the WebView reports layout late.
    setTimeout(function () { map.invalidateSize(); }, 300);
  }

  function animateEntrance() {
    if (typeof gsap === 'undefined') return; // static fallback, no fake claim
    try {
      gsap.from('.card', { y: 24, opacity: 0, duration: 0.6, stagger: 0.08, ease: 'power2.out', clearProps: 'all' });
    } catch (err) {
      /* static content remains — animation is enhancement only */
    }
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
