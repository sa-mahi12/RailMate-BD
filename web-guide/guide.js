// B09 station guide scaffold script — vanilla JS only, fully offline.
//
// B09 NOTE (R-15 BLOCKED): GSAP entrance-animation wiring goes here ONLY
// after teacher approval for embedded web technologies is recorded.
// Until then: no CDN scripts, no animation library, no network calls.
// Approved post-approval step: animate `.card` elements on load with a
// locally vendored GSAP bundle (never a CDN URL).
//
// B09 NOTE (R-09/R-10 BLOCKED): YouTube/Maps embed injection goes here
// ONLY after teacher approval. The #map-slot and #video-slot divs stay as
// local placeholder text until then.

(function () {
  'use strict';

  function markReady() {
    document.body.setAttribute('data-guide-ready', 'true');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', markReady);
  } else {
    markReady();
  }
})();
