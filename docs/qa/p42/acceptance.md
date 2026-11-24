# P42 acceptance — requirement by requirement

Each row says what was asked, what exists, and what was actually observed. Test
kinds are labelled: **UNIT**, **HOSTED**, **BROWSER**, **CI**. No row claims a
device observation, because none was made in this packet.

| # | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Public site on free hosting, fetching real Supabase data (not a static mockup) | **DONE** | `https://sa-mahi12.github.io/RailMate-BD/` deployed by `deploy-pages.yml` (**CI** success runs 45452161331, 45452629320, 45453214538, 45454328891). BROWSER: three real posts, real comment, real counts |
| 2 | Media stays in Supabase Storage, never in GitHub | **DONE** | HOSTED run `mwuyl77s16e9`: PNG/WebM/PDF uploaded through the Storage API into `post-media`; the page links `…/storage/v1/object/public/post-media/…`. The repository contains only source and two browser screenshots |
| 3 | Permanent post links open the exact post — in a browser and in the Android app | **BROWSER PASS / APP UNIT-TESTED** | `post.html?id=<uuid>` verified live with title, comments and engagement; `railmatebd://post/<uuid>` (alias `railmate://post/<uuid>`) parsed by `parsePostLink`, intent filters added, covered by `p42_post_links_test.dart`. No phone tap-through |
| 4 | Composer: several images, uploaded video, documents, external video links, ordinary URLs | **DONE (app UI unit-tested, hosted round-trip observed)** | Composer buttons Photos/Camera/Video/File/Link with reorder, remove and retry (`p42_compose_attachments_test.dart`: 10-item cap, duplicate links, upload-then-insert order, honest failure). HOSTED: five attachment rows (image, video, PDF, YouTube link, plain link) written by account A and read by an anonymous reader and by account B |
| 5 | Attachments actually upload and render for other users | **DONE** | HOSTED + BROWSER: second account and an anonymous reader see all five; deployed page rendered the image, an HTML5 player, a PDF card, a click-to-load YouTube button and a link card |
| 6 | Show the real author's public name, username and profile; never private info | **DONE** | `public_profile_cards` exposes only `id, username, display_name, joined_at, post_count`; HOSTED check asserts no other field; BROWSER profile page shows `P42 Amina (demo) · @p42_amina_7s16e9 · Joined Nov 24 · 1 post` |
| 7 | Preserve comments, likes/dislikes, post ratings and realtime; two accounts see the same changes | **PRESERVED** | Existing tables/policies/channels untouched; `public_post_stats` aggregates likes, dislikes, rating count/average and comments. HOSTED: B's comment, LIKE and 5-star rating are visible to an anonymous reader as `1 like / 5.0 ★ (1) / 1 comment`. Realtime itself was verified in earlier packets (R-02/R-03/R-07); this packet did not re-run a two-screen realtime observation |
| 8 | Add post reporting and user reporting | **DONE** | `post_reports` / `user_reports` with constrained reasons, one row per reporter, reporter-only read, no self-report. HOSTED: B's report stored and invisible to the author; self-report rejected (400) |
| 9 | Post ratings stay separate from personal reputation; no arbitrary person ratings | **DONE** | Ratings live on `post_ratings(post_id, user_id, stars)`; P42 adds no person score anywhere, and reports never modify a rating |
| 10 | Baseline `v1.0.0+28` preserved; publish the next signed release if the app changes | **DONE** | `v1.0.0+29` from release run 45453959869 (8 assets, SHA256 verified, `versionCode 29`, same signing certificate); `v1.0.0+28` and its assets unchanged |
| 11 | Publish source, migrations, tests and docs | **DONE** | `main` commits `c8565cd` … `057909d`; migration `20261124000001_p42_social_web.sql`; 36 new Flutter tests + 10 site tests; `docs/P42_SOCIAL_WEB.md`, `docs/moderation/p42-moderation.md`, `docs/qa/p42/` |
| 12 | Deploy and verify the actual public URL | **DONE** | Live URL opened in real Chrome, data rendered, video measured playing, screenshots in `docs/qa/p42/site-live-*.png` |
| 13 | Teacher-gate evidence (Datepicker, Tailwind/Sass, Rating, Embedded video, Maps, Animations, GraphQL/tRPC) | **UNCHANGED + SASS/VIDEO STRENGTHENED** | Datepicker R-14, rating R-07, animations R-15, maps R-10 (OSM, deviation), GraphQL R-18 unchanged. Sass now has a second live consumer (the deployed stylesheet is compiled from `styles.scss`); embedded video now has both an uploaded-video lane and an allowlisted YouTube embed, verified in a real browser |
| 14 | No real money, DEMONSTRATION ONLY | **DONE** | Payments remain simulated; attachments and tickets state demonstration only; the site footer states no real tickets, payments or reservations |

## Deliberately not claimed

* Per-post Open Graph previews (static hosting has no per-post HTML).
* Website writes: the page is a read-only public view; the app writes.
* Website realtime: it polls every 20 s; the app is the realtime client.
* Android device verification of the composer, the attachment renderers or the
  deep links. Unit tests and hosted round-trips are strong evidence that the
  code path works, and they are not a substitute for a phone run.
