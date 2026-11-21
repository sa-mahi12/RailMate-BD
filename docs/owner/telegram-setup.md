# Telegram phone verification — owner setup (P41)

Status: **code complete, not deployed, not provider-verified.** The app, the
Edge Functions, the migration and the mocked-update tests are committed. Nothing
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
   below. The number is stored masked and is never shown to other travellers."*
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

Apply **one** of:

```bash
# A. CLI (needs the database password / linked project)
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push

# B. Dashboard → SQL Editor → paste the file → Run
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

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already present as hosted
function secrets (used by `book-trip` / `cancel-booking`). Do not add them to
the app.

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

Run the +27 build on a phone, signed in with a **test account**:

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

Row check (SQL editor):

```sql
select status, method, phone_masked, verified_at is not null as verified,
       telegram_user_id is not null as bound
  from public.phone_verifications
 order by created_at desc limit 5;
```

Expected: `status = verified`, `method = telegram_contact`,
`phone_e164` populated, `phone_masked` masked, `auth.users.phone_confirmed_at`
still `null` for that account.

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
