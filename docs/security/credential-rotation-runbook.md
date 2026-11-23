# Credential rotation runbook (RailMate BD, 2026-11-20)

Nothing in this file has been executed. Rotation is **owner-only**: it changes
hosted credentials and can interrupt applications and sessions. The exact
impact depends on the project's active API/signing keys. Do not execute these
steps in an automated agent session.

Why this exists: the public app repository history contains a service-role JWT
that was committed in `app.env.json` between 2026-10-02 and 2026-10-14 (see
`security-audit-2026-11-20.md`). Because the repository is public and history
cannot be rewritten under this project's governance, the value must be treated
as compromised.

---

## 1. What to rotate, where it lives, what breaks

| Credential | Current location | Consumers | Rotation blast radius |
|---|---|---|---|
| Legacy Supabase **JWT secret** | Dashboard → JWT signing keys | Legacy API JWTs and any component trusting the old signer | Revocation can invalidate old access tokens; inspect signing-key state and verify, do not assume every refresh session is revoked |
| Supabase **anon/publishable** key | Dashboard → Settings → API Keys | CI variables, Flutter builds, local runs | Disabling legacy API keys breaks installed builds still using anon; update clients first unless active abuse demands immediate retirement |
| Supabase **service-role/secret** key | Platform-injected function environment | `book-trip`, `cancel-booking`, `telegram-challenge`, `telegram-webhook` | Adapters currently read legacy variables; disabling legacy keys requires a reviewed adapter migration and hosted smoke tests |
| **Telegram bot token** | hosted function secret only | `telegram-webhook` | Verification stops; nothing else |
| **Telegram webhook secret** | hosted function secret + `setWebhook` | `telegram-webhook` header check | Webhook returns 401 (fails closed) |
| **OpenRouter key** | user device only (Android Keystore) | user's own device | Only that user's AI rewrite |
| **Release keystore** | GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, passwords, alias) | release workflow | Changing it makes future APKs un-updatable over installed ones — do not rotate without a migration plan |
| **Database password** | owner password manager | `supabase db push` / `psql` | Nothing at runtime; only CLI access |

## 2. Order of operations (Supabase)

1. **Inventory privately:** project ref, deployed functions, CI variable
   names, installed apps, API key types and JWT signing-key state. Do not print
   key values. If there is active abuse, the owner must decide whether to
   retire the compromised key immediately despite downtime.
2. Dashboard → **Settings → API Keys**: create a publishable key and a new
   secret key. Creating replacements alone does **not** revoke legacy keys.
3. **Compatibility gate:** commission a reviewed change from the functions'
   legacy `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` reads to the
   platform-injected `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS`
   dictionaries (select the correct key name). Validate JWT authentication,
   REST, booking/cancellation and webhook authentication. That code change is
   not implemented by this documentation packet. Custom secret names starting
   with `SUPABASE_` are reserved and rejected; never run `supabase secrets set`
   for them. New API keys are not JWTs and must not be used as user bearer JWTs.
4. Owner deploys the reviewed compatible functions:

   ```bash
   supabase functions deploy book-trip
   supabase functions deploy cancel-booking
   supabase functions deploy telegram-challenge
   supabase functions deploy telegram-webhook --no-verify-jwt
   ```

5. Update the release workflow's public client variable to the new publishable
   key (the existing `SUPABASE_ANON_KEY` variable name is retained by the
   build). Supply values privately; the examples are placeholders:

   ```bash
   gh variable set SUPABASE_URL --body 'https://<ref>.supabase.co'
   gh variable set SUPABASE_ANON_KEY --body '<new publishable key>'
   ```

6. Publish and install a compatible signed build; privately update or remove
   local key files. Prove new-key public REST, login, protected reads, booking,
   cancellation, configured/unconfigured Telegram behaviour and existing/new
   session behaviour before retirement. Do not infer any HTTP code without
   observing it.
7. **Retire:** Dashboard → API Keys → deactivate legacy keys. Also migrate to
   JWT signing keys and revoke the legacy JWT secret as directed by Supabase's
   signing-key guide. Verify the exposed legacy credential is rejected on all
   relevant API/function paths; never restore it to recover a missed client.
   Do not put the compromised value in logs or evidence. Record only date,
   path and observed status.

## 3. Revoking the exposed historical value

Replacement keys do not revoke the historical credential. Legacy-key
deactivation and legacy JWT secret revocation are separate required gates.
Their completion is **NOT VERIFIED** here. Do not rely on deleting a file or
rewriting history; public copies can persist. Any GitHub cache-removal request
is owner-side and not a substitute for revocation.

Official references checked 2026-11-21:
[rotate a leaked key](https://supabase.com/docs/guides/security/rotate-leaked-api-keys),
[function environment variables](https://supabase.com/docs/guides/functions/secrets),
[JWT signing keys](https://supabase.com/docs/guides/auth/signing-keys).

## 4. Telegram rotation

* Token: BotFather → `/revoke` → new token →
  `supabase secrets set TELEGRAM_BOT_TOKEN='...'` → re-register the webhook:
  `setWebhook` with the same URL and `secret_token`.
* Secret: `openssl rand -hex 32` → `supabase secrets set
   TELEGRAM_WEBHOOK_SECRET='...'` → `setWebhook` with the new
  `secret_token`. Between the two calls Telegram's header mismatches and the
  function returns 401 (fails closed, no verification succeeds).

## 5. OpenRouter (user key)

Delete/disable the key on openrouter.ai, then remove it in the app (AI Settings
→ Remove key). The app deletes it from secure storage and stops offering
rewrite.

## 6. Repository visibility

Both repositories are public. If the owner wants them private:
`gh repo edit --visibility private --accept-visibility-change-consequences`
(owner action; the agent did not change visibility). If they stay public, the
`docs/owner/` guides and this runbook stay safe because they contain no secret
values — keep it that way.

## 7. Checklist after rotation

- [ ] Replacement API keys and compatible function adapters verified
- [ ] Legacy API keys disabled and legacy JWT signer revoked; old credential rejected
- [ ] Owner deployments and hosted booking/cancellation/auth smoke tests pass
- [ ] CI variables updated; compatible signed release installed
- [ ] Booking + cancellation verified on a device
- [ ] Telegram webhook re-registered (if the bot is deployed)
- [ ] `app.env.json` updated or deleted
- [ ] No new secret committed (`git status`, secret scan re-run)
- [ ] This document updated with the rotation date (no values)
