# P42 evidence index

Everything here was produced against the **hosted** RailMate BD Supabase project
(`psuzlyingfmstnyfvlnj`) and the deployed GitHub Pages site. No mocks are
presented as evidence. Test kinds are labelled explicitly: **UNIT** (offline
fakes), **HOSTED** (real database/Storage), **BROWSER** (real Chrome on the
deployed page).

| Evidence | Kind | What it shows |
| --- | --- | --- |
| `cross-account-evidence.json` | HOSTED | two independent accounts: A publishes a post with image + video + PDF + YouTube link + plain link; an anonymous reader and B see all five; B comments/likes/rates; public stats reflect it; B cannot delete A's post; B's report is stored and hidden from A; non-HTTPS link, foreign-owned attachment and self-report are rejected by the database |
| `site-local-feed.png` | BROWSER | the site rendered from live data during local verification |
| `site-local-post.png` | BROWSER | one post permalink with attachments, engagement and comments |
| `site-live-feed.png` | BROWSER | the deployed `https://sa-mahi12.github.io/RailMate-BD/` page |
| `site-live-post.png` | BROWSER | the deployed post permalink |
| `video-playback.txt` | BROWSER | the uploaded WebM played in Chrome (`paused=false`, `currentTime` 2.46 s, 848×480) |

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
deleted) so the public site has real content to show.

## Browser run (BROWSER)

Real Chrome, deployed page, no devtools protocol shortcuts:

1. `https://sa-mahi12.github.io/RailMate-BD/` shows the demo post with its
   image, video player, PDF card, provider-embed button and link card, plus the
   two legacy posts with honest "Photo unavailable" fallbacks.
2. `post.html?id=<uuid>` shows the same post, its comments (author identity +
   timestamp) and the engagement pills.
3. The video element played: `currentTime` advanced to 2.46 s of 20.4 s at
   848×480 with `paused: false`.
4. The YouTube attachment renders a **click-to-load** button, not an
   auto-loaded iframe.

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
* `site/assets/util.test.mjs` — the website's pure helpers (`npm test`).

## Not claimed

* Per-post Open Graph previews (static hosting limitation, documented).
* Website writes (the site is a read-only public view).
* Realtime on the website (it polls every 20 s; the app is the realtime client).
* Android *device* verification of the new deep links — the intent filters and
  parsers are unit-tested, and the app-side screens are covered by widget-level
  code paths, but no physical-phone tap-through was recorded in this packet.
