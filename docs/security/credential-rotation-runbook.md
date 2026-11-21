# Credential rotation runbook (RailMate BD, 2026-11-20)

Nothing in this file has been executed. Rotation is **owner-only**: it changes
hosted credentials and (for the Supabase JWT secret) invalidates every existing
session and key at once. Do not run these steps in an automated agent session.

Why this exists: the public app repository history contains a service-role JWT
that was committed in `app.env.json` between 2026-10-02 and 2026-10-14 (see
`security-audit-2026-11-20.md`). Because the repository is public and history
cannot be rewritten under this project's governance, the value must be treated
as compromised.

---

## 1. What to rotate, where it lives, what breaks

| Credential | Current location | Consumers | Rotation blast radius |
|---|---|---|---|
| Supabase **JWT secret** (regenerates `anon` + `service_role`) | Supabase dashboard → Project Settings → API → JWT Settings | Flutter builds (`SUPABASE_ANON_KEY`), Edge Functions (`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`), GitHub Actions variables, local `app.env.json` | All signed-in sessions end; every deployed function must be redeployed with the new secrets |
| Supabase **anon/publishable** key | as above | CI variables `SUPABASE_ANON_KEY`, local runs | App cannot reach the API until updated |
| Supabase **service-role** key | hosted function secrets | `book-trip`, `cancel-booking`, `telegram-challenge`, `telegram-webhook` | Booking/cancellation and Telegram verification fail closed (HTTP 500) until updated |
| **Telegram bot token** | hosted function secret only | `telegram-webhook` | Verification stops; nothing else |
| **Telegram webhook secret** | hosted function secret + `setWebhook` | `telegram-webhook` header check | Webhook returns 401 (fails closed) |
| **OpenRouter key** | user device only (Android Keystore) | user's own device | Only that user's AI rewrite |
| **Release keystore** | GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, passwords, alias) | release workflow | Changing it makes future APKs un-updatable over installed ones — do not rotate without a migration plan |
| **Database password** | owner password manager | `supabase db push` / `psql` | Nothing at runtime; only CLI access |

## 2. Order of operations (Supabase)

1. **Snapshot**: recorded project ref, deployed function list
   (`supabase functions list`), current CI variables (`gh variable list`).
2. Dashboard → Project Settings → API → **JWT Settings → Generate new JWT
   secret**. Copy the new `anon` and `service_role` keys immediately.
3. Update hosted function secrets:

   ```bash
   supabase secrets set \
     SUPABASE_ANON_KEY='<new anon>' \
     SUPABASE_SERVICE_ROLE_KEY='<new service_role>'
   ```

   (`SUPABASE_URL` is unchanged.)
4. Redeploy every function so the new env is loaded:

   ```bash
   supabase functions deploy book-trip
   supabase functions deploy cancel-booking
   supabase functions deploy telegram-challenge
   supabase functions deploy telegram-webhook --no-verify-jwt
   ```

5. Update CI variables used by the release workflow:

   ```bash
   gh variable set SUPABASE_URL --body 'https://<ref>.supabase.co'
   gh variable set SUPABASE_ANON_KEY --body '<new anon>'
   ```

6. Update `app.env.json` on the developer machine (or delete it) and any local
   `--dart-define` scripts. Never commit it.
7. Verify:
   * anonymous REST call with the new anon key succeeds; the old key returns
     `401 Invalid JWT`;
   * sign in on a device, book a trip, cancel it (real hosted calls);
   * `telegram-challenge` without a bot returns `503 TELEGRAM_NOT_CONFIGURED`,
     not `500`;
   * `telegram-webhook` without the secret header returns `401`;
   * old sessions are invalidated — this is expected, sign in again.

## 3. Revoking the exposed historical value

Rotating the JWT secret already makes the leaked `service_role` JWT unusable —
that is the revocation. Do **not** rely on deleting the file from history: the
repository was public. If GitHub support is asked to purge cached views, that is
an owner decision; it is not a substitute for rotation.

## 4. Telegram rotation

* Token: BotFather → `/revoke` → new token →
  `supabase secrets set TELEGRAM_BOT_TOKEN='...'` → redeploy
  `telegram-webhook` → re-register the webhook:
  `setWebhook` with the same URL and `secret_token`.
* Secret: `openssl rand -hex 32` → `supabase secrets set
  TELEGRAM_WEBHOOK_SECRET='...'` → redeploy → `setWebhook` with the new
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

- [ ] New JWT secret generated; old keys rejected by the API
- [ ] Four functions redeployed with new secrets
- [ ] CI variables updated; a release workflow run succeeds
- [ ] Booking + cancellation verified on a device
- [ ] Telegram webhook re-registered (if the bot is deployed)
- [ ] `app.env.json` updated or deleted
- [ ] No new secret committed (`git status`, secret scan re-run)
- [ ] This document updated with the rotation date (no values)
