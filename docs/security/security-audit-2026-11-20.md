# Security audit — 2026-11-20 (P41)

Scope: `sa-mahi12/RailMate-BD` (app), `sa-mahi12/RailMate-BD-internal` (docs),
their Git history, Edge Functions, GitHub Actions, bundled assets and the
hosted Supabase configuration as observable from the app. No secret value is
reproduced in this document.

Method (all commands run from the repository roots):

```bash
git ls-files | grep -Ei 'env|\.pem|\.jks|keystore|key\.properties'
git grep -I -E 'eyJ[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{30,}'      # JWTs
git grep -I -E 'sk-or-v1-[A-Za-z0-9]{16,}'                       # OpenRouter
git grep -I -E '[0-9]{8,10}:[A-Za-z0-9_-]{35}'                   # bot tokens
git grep -I -E '\+8801[0-9]{9}'                                  # phone numbers
git log --all -p | grep -E '<same patterns>'                     # history
gh repo view <repo> --json visibility
gh secret list --repo sa-mahi12/RailMate-BD
```

## Findings

| # | Severity | Finding | Evidence | Status |
|---|---|---|---|---|
| 1 | **HIGH** | Both repositories are **public** (`isPrivate=false`) | `gh repo view` for both repos | Accepted as-is by the owner’s earlier decision; review recommended |
| 2 | **HIGH** | A **service-role JWT** was committed inside `app.env.json` and is still reachable in the public repository **history** (first seen 2026-10-02, last commit containing it 2026-10-14). Current `HEAD` contains no JWT. | `git grep` over `git rev-list --all` hit `app.env.json` in 30 commits; payload `role` claim decoded as `service_role` | **Must rotate** (owner). History rewrite is forbidden in this project, so the key must be treated as permanently exposed |
| 3 | Medium | The same historical file also exposed the project **anon** JWT | same scan; `role=anon` | Rotates together with the JWT secret |
| 4 | Medium | A working `app.env.json` with `SUPABASE_SERVICE_ROLE_KEY` still exists on the developer machine (gitignored, never tracked at HEAD) | `git check-ignore -v app.env.json`; file present locally | Delete after owner rotation; keep out of backups/screenshots |
| 5 | Low | The hosted project ref (`psuzlyingfmstnyfvlnj`) appears in docs/CI variables | public by design (it is part of the API URL) | No action |
| 6 | Info | No OpenRouter key (`sk-or-v1-…`) in tracked files or history of either repo | `git grep` + `git log -p` | Clean |
| 7 | Info | No Telegram bot token (`<digits>:<35 chars>`) in tracked files or history | `git grep` + `git log -p` | Clean |
| 8 | Info | No keystore, `.jks`, `.p12`, `key.properties` tracked; release signing uses GitHub Secrets | `git ls-files`; `.github/workflows/release.yml` | Clean |
| 9 | Info | GitHub Secrets contain only signing material: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | `gh secret list` (names only) | No Supabase/OpenRouter/Telegram secrets in CI — correct |
| 10 | Info | The only phone-number-shaped string in the internal docs is the standard placeholder `+8801712345678` (one distinct value, one file) | `git grep '\+8801[0-9]{9}'` | Not personal data |
| 11 | Info | App source contains no bot token, bot username or webhook secret; enforced by `test/telegram_production_wiring_test.dart` | test suite | Clean by construction |
| 12 | Info | Edge Functions read secrets only from the hosted environment; `.env.example` files are empty placeholders | `supabase/functions/*/.env.example` | Clean |
| 13 | Info | New Telegram tables use RLS with a read-own policy and **no** client write policy; writes use the service role; the webhook validates `X-Telegram-Bot-Api-Secret-Token` with a constant-time compare | `supabase/migrations/20261120000001_…sql`, `telegram-webhook/index.ts` | Design control |
| 14 | Info | No `print`/`debugPrint`/`developer.log` in the AI slice; user-facing errors never echo the key | `test/r23_audit_test.dart` | Clean |

## What is *not* claimed

* No GitHub-hosted secret scanning or Dependabot result is claimed; only the
  manual scans above were run.
* The hosted Supabase dashboard configuration (Auth providers, SMTP, rate
  limits, function secrets) could not be inspected from this environment; the
  agent has no dashboard or database password.
* No penetration test was performed.

## Priority action for the owner

Rotate the Supabase **JWT secret** (which invalidates the old `anon` and
`service_role` keys) and update every consumer. Do this before sharing the
repository link with anyone else. See
[`credential-rotation-runbook.md`](credential-rotation-runbook.md).
