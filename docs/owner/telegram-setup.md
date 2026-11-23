# Telegram phone verification — owner setup (P41)

Status: **corrective source for +28, not deployed, not provider-verified.** The original
implementation is committed at `8df1654`/`+27`; the corrective app/backend/schema
changes target a separate +28 release; consult the P41 closure for publication evidence. Nothing
below has been executed by the agent, because it needs the owner's Telegram bot
and privileged Supabase access.

Telegram contact sharing is the proposed **alternative to SMS OTP**. It is not
an SMS check: no SMS is sent and `auth.users.phone_confirmed_at` is never
written. The verification method stored in the database is `telegram_contact`.

---

## 0. What the owner must supply

| Value | Where it lives | Notes |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | hosted Edge Function secret | From BotFather; never in git, the app, docs or CI |
| `TELEGRAM_BOT_USERNAME` | hosted Edge Function secret | Without `@` (e.g. `railmate_bd_bot`); used to build `https://t.me/<bot>?start=<token>` |
| `TELEGRAM_WEBHOOK_SECRET` | hosted Edge Function secret | Random string; Telegram echoes it in `X-Telegram-Bot-Api-Secret-Token` |

Generate the webhook secret:

```bash
openssl rand -hex 32        # or: python -c "import secrets;print(secrets.token_hex(32))"
```

## 1. Create the bot with BotFather

1. In Telegram, open **@BotFather** → `/newbot`.
2. Choose a display name (e.g. `RailMate BD Verification`) and a username ending
   in `bot` (e.g. `railmate_bd_verify_bot`).
3. Copy the token once and store it in a password manager. Do not paste it into
   chat, documents, screenshots or this repository.
4. `/setdescription` — paste the explanation used in the bot chat:
   *"RailMate BD phone verification. Share your own number with the button
   below. Your number is stored in a protected verification record and shown
   masked in RailMate. It is not shown to other travellers."*
5. `/setcommands` → `start - Start phone verification`.
6. Optional: `/setjoingroups` → **Disable** (the flow rejects group chats).

## 2. Apply the database migration

The migration is staged at:

```
supabase/migrations/20261120000001_telegram_phone_verification.sql
```

It is additive: two new tables (`phone_verifications`,
`telegram_webhook_updates`), one partial unique index per active challenge,
one partial unique index per verified Telegram identity, RLS read-own for the
app and service-role-only writes. It does not touch `auth.users`, `profiles`,
bookings or the SMS lane.

The corrected staged schema also records `verification_update_id` to recover
an ambiguous consume result, plus processing/completed update claims with
two-minute reclaimable leases. The backend returns HTTP 503 on a transient
failure or busy claim so Telegram can retry; only completed updates dedupe
permanently. The owner must review/apply this corrected schema together with
the corrected functions, not mix the old ledger with the new adapter. These
properties have mocked-update/HTTP-handler tests only; hosted/RLS execution is
unverified. A verification-success chat notification is best effort after the
protected write; the app's server row remains authoritative if Telegram is down.

Review the exact pending migration scope before applying:

```bash
# A. CLI (needs the database password / linked project)
supabase link --project-ref "$SUPABASE_PROJECT_REF"
# Review the linked project's pending migration list before db push; do not
# apply unrelated migrations blindly. Otherwise use the exact SQL file below.
supabase db push --dry-run

# B. Owner: Dashboard → SQL Editor → paste the exact reviewed file → Run
# Or, after reviewing the dry-run list and approving every pending migration,
# the owner may run supabase db push. The agent does not run it.
```

Verify (SQL editor):

```sql
select count(*) from public.phone_verifications;              -- 0
select relrowsecurity from pg_class
 where oid = 'public.phone_verifications'::regclass;          -- true
```

Expected result: the migration applies with no error and the tables exist.
If it fails, nothing is half-applied except the statements before the failure —
read the error, do not "fix" it by disabling RLS.

## 3. Set the Edge Function secrets

```bash
supabase secrets set \
  TELEGRAM_BOT_TOKEN='...' \
  TELEGRAM_BOT_USERNAME='railmate_bd_verify_bot' \
  TELEGRAM_WEBHOOK_SECRET='...'
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
platform-injected legacy variables used by these adapters. Do not set custom
`SUPABASE_` secrets or add privileged keys to the app. If legacy keys are
disabled during rotation, the adapters need a reviewed migration to the
platform's new publishable/secret key dictionaries before deployment; see the
rotation runbook.

## 4. Deploy the two functions

```bash
# Authenticated challenge creation/cancel: keep JWT verification ON.
supabase functions deploy telegram-challenge

# Telegram calls this directly, so JWT verification is OFF and the shared
# secret header is the authentication (timing-safe compare in index.ts).
supabase functions deploy telegram-webhook --no-verify-jwt
```

Expected results:

* `telegram-challenge` returns `401` without a bearer token and
  `503 {"code":"TELEGRAM_NOT_CONFIGURED"}` if the bot username secret is
  missing (this is what the app shows honestly).
* `telegram-webhook` returns `401` when the secret header is absent or wrong.

## 5. Register the webhook with Telegram

```bash
curl -sS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/telegram-webhook" \
  -d "secret_token=$TELEGRAM_WEBHOOK_SECRET" \
  -d "allowed_updates=[\"message\"]"
```

Check it:

```bash
curl -sS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo"
```

Expected: `url` matches, `pending_update_count` settles to 0, `last_error_message`
absent.

## 6. End-to-end verification (owner action)

After coordinator review/publication of a **new corrected signed build** and
owner backend setup, run it on a phone with a **test account**. Do not use +27
for closure: it contains the reviewed account/lifecycle defects.

1. Profile → **Phone verification** → **Verify with Telegram**.
2. Telegram opens the bot with `/start <token>`.
3. The bot replies with the explanation and a **Share my phone number** button.
4. Tap it and share your own number.
5. Bot replies "Your phone number is verified successfully…".
6. Return to the app within five minutes; the section shows
   **Phone verified — +880\*\*\*\*\*5678** (masked) and the method note.
7. Negative checks: typing a number in the bot is rejected; another Telegram
   account cannot complete the same link; the same Telegram account cannot be
   linked to a second RailMate account.
8. Account/lifecycle checks: log out of A and sign in as B; A's masked number
   must disappear. Cancel while a poll is pending, then start a fresh challenge;
   late results must not verify it. Test retries after a transient backend error.
9. Telegram may supply an international number without `+`; a sender-owned
   card is canonicalized, while a typed number never verifies an account.

Row check (SQL editor):

```sql
select status, method, phone_masked, verified_at is not null as verified,
       telegram_user_id is not null as bound
  from public.phone_verifications
 order by created_at desc limit 5;
```

Expected: `status = verified`, `method = telegram_contact`,
`phone_e164` populated, `phone_masked` masked, `auth.users.phone_confirmed_at`
unchanged from its prior value for that account (null for a fresh account
without any earlier SMS verification).

## 7. Revocation / rotation

* **Rotate the bot token:** BotFather → `/revoke` → new token →
  `supabase secrets set TELEGRAM_BOT_TOKEN='...'` → re-run `setWebhook`.
  Old token stops working immediately.
* **Rotate the webhook secret:** generate a new one, `supabase secrets set`,
  then re-run `setWebhook` with the new `secret_token`. Until the second step,
  Telegram's header no longer matches and the function returns `401` (fails
  closed).
* **Delete the bot:** BotFather → `/deletebot`. Then remove the secrets and the
  webhook (`deleteWebhook`).

## 8. What still needs teacher acceptance

The original requirement says "email and phone verification". Telegram contact
sharing is implemented as the phone lane's alternative. Until the owner
configures the bot **and** the teacher accepts the substitution, the requirement
stays recorded as *implemented alternative, acceptance pending* — never PASS.
