# P42 evidence index

Everything here was produced against the **hosted** RailMate BD Supabase project
(`psuzlyingfmstnyfvlnj`) and the deployed GitHub Pages site. No mocks are
presented as evidence. Test kinds are labelled explicitly: **UNIT** (offline
fakes), **HOSTED** (real database/Storage), **BROWSER** (real Chrome on the
deployed page).

| Evidence | Kind | What it shows |
| --- | --- | --- |
| `cross-account-evidence.json` | HOSTED | run `mwv0r1ce33dd` (22 checks): two independent accounts — A publishes a post with image + video + PDF + YouTube link + plain link; an anonymous reader and B see all five; B comments/likes/rates; public stats reflect it; B cannot delete A's post; B's report is stored and hidden from A; non-HTTPS link, foreign-owned attachment, foreign storage path and self-report are rejected; a repeat report updates instead of erroring; a client-supplied `created_at` is replaced by the server clock |
| `site-live-feed.png` | BROWSER | the deployed feed at `https://sa-mahi12.github.io/RailMate-BD/` with the demo post, its image, video player, PDF card, provider-embed button and link card |
| `site-live-post.png` | BROWSER | the deployed permalink `post.html?id=351fcc82-45e7-4218-a7c9-ca20f61fc779` with the same post, `1 like / 5.0 ★ (1) / 1 comment` and the comment written by account B |
| `site-live-profile.png` | BROWSER | the deployed public profile `profile.html?id=9993d125-e4f1-45f9-8f45-025b5cc23bb7`: display name, `@username`, join date, `1 post` and that author's post — no email, phone or booking data |
| `site-local-feed.png` | BROWSER | the same build served locally (offline comparison of feed layout) |
| `site-local-post.png` | BROWSER | the same build served locally (post page) |
| `video-playback.txt` | BROWSER | the uploaded WebM playing on the deployed page: `paused=false`, `currentTime` advancing, 848×480, same element still playing 37.7 s later across a 20 s refresh boundary |

## Cross-account run (HOSTED)

Produced by:

```powershell
node scripts/p42_cross_account_evidence.mjs
```

The script creates two throw-away accounts (`p42.a.<run>@example.com`,
`p42.b.<run>@example.com`), gives them public usernames, and runs the whole
matrix with the real REST + Storage APIs. It prints only pass/fail lines; the
JSON holds ids, status codes and counts — never a key, token or password. The
accounts are synthetic demo accounts, deliberately **not** the owner's two real
accounts.

The generated demonstration post stays on the board (one per run; older runs are
deleted) so the public site has real content to show. Run
`mwuykdp96f00` first failed on a genuine client bug (`PGRST102`: PostgREST
requires identical keys on every object of a bulk insert) and run `mwuyl77s16e9`
was the first stored pass; `mwv0r1ce33dd` is the current pass after the review
follow-up. Because a newer run removes the previous run's post, the screenshots
below were captured during the run named in their caption, and an old permalink
in this document may legitimately answer "This post is not available".

## Review follow-up (2026-11-25)

An independent read-only review of the live schema and the client code found no
Critical issue and one Important one worth fixing immediately:

* **Important — storage path was not bound to the owner.** The check constraint
  only required `<uuid>/…`. A signed-in user could therefore make their own
  attachment row point at *another* user's object, display it on their post, and
  — through a later cleanup keyed on the path — target a foreign file.
  `20261125000001_p42_hardening.sql` adds
  `post_attachments_path_owner_chk` (`split_part(storage_path, '/', 1) =
  owner_id::text`), validated against the existing rows.
* The same migration also: applies the ten-attachment cap on UPDATE when
  `post_id` changes (moving rows between own posts can no longer exceed it),
  stamps `posts`/`post_comments.created_at` from the server clock so a backdated
  insert cannot bypass the rate limit, allows a reporter to update their own
  report, and stops an author from reporting their own post.
* `20261125000002_p42_report_upsert.sql` resolves a repeat report inside the
  database (the shipped `+29` client upserts without naming the conflict
  target, which PostgREST cannot resolve), so a second report updates the first
  row instead of failing with 409.

The reviewer also raised three items accepted as follow-ups rather than fixed
here because they need a Dart change and a new APK: website-only
`http://` acceptance in the link parser (ids are still uuid-validated, no open
redirect), the `attachments_read` policy being `using (true)` (no new leak while
`posts` is fully public, but it must be revisited if post moderation is added),
and a recovery-link double-handling path in the pre-existing auth code, which is
older than P42 and unrelated to this packet.

Items 1–2 of that list are *now* fixed in the database and re-verified by the
22-check hosted run above.

## Browser run (BROWSER)

Real Chrome, the deployed page:

1. `https://sa-mahi12.github.io/RailMate-BD/` shows three real posts. The demo
   post renders its image, an HTML5 video player, a PDF file card, a
   click-to-load YouTube button and a plain link card, plus `1 like`, `5.0 ★ (1)`
   and `1 comment`.
2. `post.html?id=351fcc82-45e7-4218-a7c9-ca20f61fc779` shows the same post,
   `Comments (1)` authored by `P42 Rafi (demo) · @p42_rafi_ce33dd`, and the
   document title becomes `P42 Amina (demo) on RailMate BD`.
3. The video played on the deployed page (`video-playback.txt`).
4. `profile.html?id=9993d125-e4f1-45f9-8f45-025b5cc23bb7` shows
   `PA · P42 Amina (demo) · @p42_amina_ce33dd · Joined Nov 25 · 1 post` and one
   post; the page reads only the `public_profile_cards` view, so no email,
   phone, Telegram identity or booking row is ever requested.
5. The two legacy pre-P42 posts render "Photo unavailable" for their missing
   Storage objects instead of a broken image icon.

## What is unit-tested (UNIT)

* `test/p42_attachment_model_test.dart` — kinds, MIME→kind/extension mapping,
  storage path rules, https-only links, provider allowlist, row parsing.
* `test/p42_post_links_test.dart` — canonical permalinks, app deep links,
  share text bounds, link parsing (including rejecting foreign hosts).
* `test/p42_compose_attachments_test.dart` — draft validation, 10-item cap,
  duplicate links, reorder, upload-then-insert order, honest failure and retry,
  report reason sets.
* `test/p42_post_author_test.dart` — `Post` parsing with embedded attachments,
  legacy rows, safe public profile card (ignores private fields if present).
* `site/assets/util.test.mjs` — the website's pure helpers (`npm test`):
  https-only links, provider allowlist, strict uuids, permalinks, initials and
  human formatting.

Full suite at the P42 commit: **675 Flutter tests**, 10 site tests,
`flutter analyze` clean, `dart format` clean.

## CI

* Pull-free `main`-only workflow runs for the P42 commits:
  - `45451935841` (96754ab) — Flutter CI success
  - `45451672940` (c8565cd) — Flutter CI success
  - deploy-pages runs for each commit; the first two failed on a real unit-test
    failure (`initialsFor('P42 Amina (demo)')` returned `PD`) and on Pages not
    being enabled, both fixed rather than re-run blindly.
* Pages was enabled by the owner identity (`gh api -X POST …/pages`); the
  workflow's own `enablement: true` was rejected with "Resource not accessible
  by integration" for the workflow token.

## Signed release

`v1.0.0+29` was published by release run `45453959869` from `84dd332` (the app
code is identical at `main` today; later commits touched `site/` and `docs/`
only). Verified after download, not from the log:

* eight assets: universal APK, three split APKs (arm64-v8a, armeabi-v7a,
  x86_64), AAB, `SHA256SUMS.txt`, `release-manifest.json`, `PROVENANCE.md`;
* universal APK SHA256 `e2d67d17415393b1403b07d60e0e8984a237669537ce83a5a7aa5e890608eac6`
  matches the GitHub asset digest and `SHA256SUMS.txt`;
* `aapt2 dump badging`: `bd.railmate.railmate_bd`, `versionCode='29'`,
  `versionName='1.0.0'`, minSdk 24, targetSdk 36;
* `apksigner verify --min-sdk-version 24` exit 0, certificate SHA-256
  `37c67c4c119d3adea7dcbeaae99ae69d8ab14e231ca2fecee9b6134190f2f155` — the same
  release certificate as `+28`, so it updates an installed build;
* the extracted `lib/arm64-v8a/libapp.so` contains the P42 symbols
  `post_attachments`, `public_profile_cards` and `post_reports`, so the shipped
  binary really includes this packet's code;
* `v1.0.0+28` and its eight assets are unchanged (no overwrite).

## Not claimed

* Per-post Open Graph previews (static hosting limitation, documented).
* Website writes (the site is a read-only public view).
* Realtime on the website (it polls every 20 s; the app is the realtime client).
* Android *device* verification of the new deep links or attachment UI — the
  intent filters, parsers and composer are unit-tested, but no physical-phone
  or emulator tap-through was recorded in this packet.
