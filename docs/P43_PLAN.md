# P43 — revised community and official timetable packet

Working record for the revised P43 phase (started 2026-11-25 from app
`f058afc`, docs `3b3812b`). The handoff bundle lives outside the repository; this
file records what was built, what is frozen, and what still needs the owner.

## Scope

1. Coherent UI across the existing four tabs (Home, Bookings, Board, Profile).
2. Official published timetable as the default discovery mode, separate from the
   academic demo booking.
3. Journey Board completion: post edit/delete + media cleanup, My Posts, comment
   replies/edit/delete/report, blocks, report receipts, staff moderation console.
4. Selective Norfold reference (behaviour/tests only, no code copied).
5. **Production Supabase frozen** until the whole release candidate is ready and
   the project owner approves the database gate.

## Hard product limits

- No SMS tracking button, composer or workflow.
- No claim of live location, delay, ETA, platform, seat inventory or live fare.
- Official schedule rows never become `trips`/`trip_seats` rows and never enter
  the demo seat-selection flow.
- Post star ratings remain ratings of a post, never of a person.
- No DMs, followers/social graph, ads, person-level reputation or generic chat.
- Public Pages stays read-only for content creation.

## Official timetable dataset

| Item | Value |
| --- | --- |
| Source | Bangladesh Railway published timetable index + Eastern/Western PDFs |
| Timetable number | 54 |
| Effective from | 2025-03-10 |
| Retrieved / last verified | 2026-11-25 |
| Eastern PDF SHA-256 | `d6e1af80252d98b45e8a07e7c30be1ec51f94ddf4b3c942daf4cc3a697137cc9` |
| Western PDF SHA-256 | `bc40965826c3f597469d1ddff402b5d78bd340ac3512c22aab944ec28d2de533` |
| Imported rows | 130 intercity directions (62 Eastern incl. 4 phased, 68 Western incl. 6 international) |
| Stations | 29, derived from the published names |
| Excluded printed rows | 4 (two unnamed phased trains 811/812, two "proposed ..... express" rows 807/808) |
| Not imported | Eastern mail/express + commuter tables (pages 3–8) and Western mail/express + commuter tables (pages 2–15) |

Why the tables were transcribed by hand: the Eastern PDF is a scan with no text
layer, and the Western PDF's text layer uses a legacy Bangla font encoding that
extracts as mojibake. Guessing rows was not acceptable, so the dataset contains
only rows that were read from the page image, with page + printed serial attached
to each row. The manifest states exactly which sections are still missing; the UI
shows that coverage line instead of pretending the dataset is complete.

`overnight_inferred` is arithmetic, not a published field: an arrival at or
before the departure time can only be on the following day, and the UI labels it
"next day (inferred)". Intermediate stops, fares, platforms and frequencies are
never derived.

### Rebuilding

```powershell
E:\Apps\Python313\python.exe tools\build_official_timetable.py
```

The builder validates times, station references, serial continuity and id
uniqueness, then writes `assets/data/official-timetable.json`,
`site/data/official-timetable.json` and `site/data/source-manifest.json`
(dataset SHA-256, PDF SHA-256, coverage gaps).

## Why Norfold reuse is reference-only

Norfold's `LICENSE.md` is PolyForm Noncommercial with a named copyright holder,
and the handoff requires the owner to confirm rights-holder authority before any
copy. Copying was therefore avoided entirely: no Norfold file, identifier,
branding, SQL migration or asset was copied. Its queue/case/audit/block patterns
informed the RailMate design only, and the RailMate implementations are
independent Dart and SQL.

## Database freeze

No hosted DDL/DML, Storage write, auth change, policy/grant change, Realtime
publication change, Edge Function deploy or secret change is part of this phase
until the owner approves the gate. Draft migrations may be committed but must not
be applied. The gate packet must list: exact migration files, object inventory,
rollback/forward-repair plan, data impact, backup/recovery point, and the hosted
checks to run afterwards.

## Status of this phase

| Area | State |
| --- | --- |
| Official timetable data + manifest | DONE (130 rows, both PDFs hashed, coverage gaps recorded) |
| Official timetable app mode | DONE (models, caching repository, query, list/detail/station screens, home entry) |
| Official timetable public page | DONE (`site/timetable.html` + pure filter module, 10 node tests) |
| Post edit/delete/My Posts | in progress |
| Comment replies/edit/delete/report | in progress |
| Moderation console, roles, blocks, receipts | in progress |
| Draft migrations | in progress (not applied) |
| UI polish pass with before/after screenshots | pending |
| Full CI + release candidate | pending |
| Owner database gate | **blocked on owner approval** |
| New Android release | **not started; `v1.0.0+29` preserved and no release without owner approval** |

## Verification so far

- `dart analyze lib/features/timetable lib/features/search lib/app` — clean.
- `flutter test test/timetable test/home` — 60 tests pass (21 new).
- `npm test` in `site/` — 20 tests pass (10 new).
- `npm run build:css` — Sass compiles.

No hosted Supabase call was made by any P43 code; the timetable reads only the
bundled asset and the public JSON.
