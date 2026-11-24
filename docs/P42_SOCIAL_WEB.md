# P42 — real social sharing on the web

Status: implemented on `main`; hosted schema applied; cross-account and browser
evidence recorded in [`docs/qa/p42/`](qa/p42/README.md). This document is the
technical reference for the packet: what exists, why it is built this way, and
what it deliberately does not claim.

## What P42 adds

| Area | Before | After |
| --- | --- | --- |
| Public web presence | none (only the bundled in-app guide) | `site/` published to GitHub Pages, reading the hosted Supabase REST API |
| Permanent post links | none | `https://sa-mahi12.github.io/RailMate-BD/post.html?id=<uuid>`, `railmatebd://post/<uuid>` (alias `railmate://post/<uuid>`) |
| Attachments | one optional image (`posts.image_path`) | up to 10 typed attachments per post: image, video, PDF/Office/ZIP/text file, external link |
| Author identity | post card with no author | safe public card (`public_profile_cards`): display name, @username, join date, post count |
| Reporting | none | `post_reports` and `user_reports`, one row per reporter per target, own-rows-only read |
| Permalinks in app | none | single-post screen (`BoardPostScreen`) + public profile screen |

Legacy rows are untouched: `posts.image_path` still renders, and the migration
mirrors each existing path into `post_attachments` exactly once
(`on conflict do nothing`, partial unique index on `(post_id, storage_path)`).

## Hosted schema (migration `20261124000001_p42_social_web.sql`)

Applied to project `psuzlyingfmstnyfvlnj` on 2026-11-24 and recorded in
`supabase_migrations.schema_migrations`. Objects:

* `public.public_profile_cards` (view) — `security_invoker = false`, granted to
  `anon, authenticated`. Only `id`, `username`, `display_name`, `joined_at`,
  `post_count`. `public.profiles` keeps its own-row-only RLS; nothing private
  is ever exposed.
* `public.post_attachments` — typed rows with check constraints:
  * `kind in ('image','video','file','link')`;
  * a link row must carry `external_url` and no `storage_path`; every other
    kind must carry `storage_path` and no `external_url`;
  * `external_url` must match `^https://[^[:space:]]+$` and be ≤ 2048 chars;
  * `storage_path` must start with a UUID folder, contain no `..`, ≤ 320 chars;
  * `file_size_bytes` ≤ 25 MiB (the bucket limit is enforced too);
  * ≤ 10 rows per post (`limit_post_attachments` trigger), owner must match the
    post owner (`guard_post_attachment` trigger, `security definer`);
  * RLS: public read, owner-only insert/update/delete.
* `public.public_post_stats` (view) — like/dislike counts, rating count and
  average, comment count. Read-only aggregate; never a personal score.
* `public.post_reports` / `public.user_reports` — reasons checked by
  constraint, one row per reporter per target, reporter-only SELECT,
  no self-report (`user_reports_no_self`).
* Rate limits: 10 posts / 30 comments per author per 10 minutes
  (`enforce_board_rate_limit`).
* `storage.buckets['post-media']`: `file_size_limit = 26214400` and an explicit
  MIME allowlist (images, MP4/WebM, MP3/M4A, PDF, text, CSV, ZIP, legacy Office,
  OOXML). Policies are unchanged (public read, owner-folder write/delete).
* Realtime publication now includes `post_attachments`; the app also keeps its
  existing `posts`, `post_comments`, `post_reactions` and `post_ratings`
  channels.

## App changes

* `lib/features/board/media/post_attachment.dart` — typed model, kind/MIME
  mapping, storage-path builder, HTTPS link validation, YouTube/Vimeo id and
  embed URL allowlist.
* `lib/features/board/media/board_attachment_picker.dart` — one picker seam
  (gallery/camera via `image_picker`, video/document via `file_picker`),
  validated **before** any upload. Size is checked from metadata before the
  bytes are read, so a 100 MB pick never allocates 100 MB.
* `lib/features/board/post/post_compose_state.dart` — `attachments` draft list
  with add/remove/reorder, `submitWithAttachments` and
  `retryFailedAttachments`. The post row is inserted first (attachments need
  its id), then each object uploads to `<uid>/<postId>/<uuid>.<ext>` and each
  row is inserted. A failure marks that item failed and stops the submit — the
  UI never claims a successful post.
* `lib/features/board/post/compose_screen.dart` — Photos / Camera / Video /
  File / Link buttons, per-item state, remove, move up/down, retry.
* `lib/features/board/media/attachment_view.dart` — per-kind rendering:
  network image, `video_player` for uploaded video, click-to-load WebView for
  allowlisted provider embeds, PDF/file cards, generic link cards. A failed
  initialise degrades to an "open externally" row.
* `lib/features/board/post/post_card.dart` — shared card used by the feed and
  the single-post screen: author header, body, attachments, engagement,
  comments, Share / Copy link / Report, relative time.
* `lib/features/board/post/post_screen.dart` — permanent-link target with
  loading, not-found and error states.
* `lib/features/board/profile/public_profile_screen.dart` — public profile
  with the author's posts and a report action.
* `lib/features/board/share/post_links.dart` + `post_actions.dart` — one place
  that builds canonical URLs, app deep links and share text; native share via
  `share_plus`, clipboard copy for the link.
* `lib/features/board/moderation/report_dialog.dart` — post/profile report
  sheet with the same reason codes the database checks.
* `lib/app/dependencies.dart` — attachment upload/insert/delete, report
  closures, `public_profile_cards` lookups, one-post and per-author queries.
* `lib/app/home_shell.dart` — wires every seam; adds a `post_attachments`
  realtime channel that triggers one bounded feed refresh (the `posts` payload
  carries no attachment columns).
* `lib/app/app_gate.dart` — parses post/profile links (app scheme **and** the
  public https permalink) and opens the right screen.
* `android/app/src/main/AndroidManifest.xml` — intent filters for
  `railmatebd://post|profile/...` and the `railmate://` alias.

## Website (`site/`)

Static HTML/CSS/JS, no bundler, no framework, published by
`.github/workflows/deploy-pages.yml`:

* `index.html` — the live feed (20 newest posts with their attachments).
* `post.html?id=<uuid>` — one post plus its comments.
* `profile.html?id=<uuid>` — public card plus that author's posts.
* `404.html` — honest "link does not point at a page" state.
* `assets/util.js` — pure helpers (https-only link validation, provider
  allowlist, uuid check, permalinks, formatting) covered by
  `assets/util.test.mjs` (`npm test`).
* `assets/app.js` — fetch + render. User text is inserted with `textContent`;
  provider embeds are built only from an allowlisted id and load after an
  explicit click, in a sandboxed iframe.
* `assets/styles.scss` → `assets/styles.css` via `npm run build:css` (Sass;
  the compiled file is committed so Pages needs no build).
* `assets/config.js` is generated at deploy time from the repository variables
  `SUPABASE_URL` and `SUPABASE_ANON_KEY`; it is gitignored, so no key is
  committed. The anon key is public by design and RLS protects every row.

The site is read-only: posting, reacting, rating and commenting happen in the
app. It refreshes itself every 20 s while the tab is visible and on focus.

## Honest limitations

* **Per-post Open Graph previews are not generated.** GitHub Pages is static
  and the crawler has no per-post HTML; a shared link shows the generic site
  title. Rendering per-post meta tags would need a server or a build step per
  post, which this prototype does not claim.
* **The website does not write.** There is no web sign-in, so it cannot like,
  rate or comment. Counts and comments are live reads.
* **Website freshness is polling-based** (20 s), not a websocket. The Android
  app is the realtime client (Supabase Realtime on five tables).
* **Uploaded video must be MP4/WebM** (the bucket allowlist). Other containers
  are rejected *before* upload with a plain-language reason rather than being
  accepted and failing later.
* **Provider embeds are YouTube and Vimeo only.** Any other link renders as a
  link card; nothing else is ever framed.
* **No automatic moderation.** Reports are stored for owner review; see
  [`docs/moderation/p42-moderation.md`](moderation/p42-moderation.md). A report
  never changes a post's rating or a person's reputation.

## Reproduce

```powershell
# app gates
flutter analyze
flutter test

# website gates
cd site
npm ci
npm test
npm run build:css

# hosted cross-account evidence (needs the gitignored app.env.json)
cd ..
node scripts/p42_cross_account_evidence.mjs
```
