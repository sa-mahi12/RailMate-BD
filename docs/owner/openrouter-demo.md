# R-23 BYOK generative AI — live demonstration procedure

Status: **CODE-COMPLETE / LIVE PROVIDER DEMONSTRATION PENDING.** No live
OpenRouter request has been made by the agent, and no key is stored anywhere in
this repository. Nothing below was executed.

## What is already implemented and tested

* User-supplied OpenRouter key in `flutter_secure_storage` (Android Keystore),
  scoped per account (`ByokVault`).
* Explicit **consent checkbox** per request; the key is read only inside the
  tap handler and passed as an argument — the HTTP client never reads the vault.
* 20-second timeout, honest error mapping (401 / 402 / 429 / network / empty
  response), no logging of key material, no auto-apply of suggestions.
* Removing the key disables the feature with a setup prompt; booking code has no
  dependency on the AI slice.
* `flutter test test/r23_audit_test.dart` covers those rules;
  `test/ai_f14_test.dart`, `test/rewrite_b11_test.dart`,
  `test/byok_vault_b10_test.dart` cover the request/response contract with a
  fake HTTP client.

## Owner demonstration (≈10 minutes)

1. Create an OpenRouter account → **Keys** → create a key. Set a small credit
   limit (the model used is `meta-llama/llama-3.1-8b-instruct`; a rewrite costs
   a fraction of a cent).
2. Install the +27 release APK on the phone and sign in with a **test** account.
3. Profile → **AI Settings** → paste the key → **Save** → **Test Connection**.
   Expected: a real completion returns; a wrong key shows "key invalid", not a
   crash and not a fake success.
4. Journey Board → create or open a draft → **Improve Wording** → tick
   "Send my key with this request only" → tap the action.
   Expected: loading state, then a suggestion that is **not** applied
   automatically; Accept applies the text, Reject leaves it untouched.
5. Turn off mobile data/Wi-Fi and repeat: expected "AI rewrite failed:
   connection failed", draft unchanged, booking/search still usable.
6. AI Settings → **Remove key** → repeat step 4: expected "No AI key saved…"
   and **zero** network requests to OpenRouter (verify with a proxy or by
   watching that the failure is instant).
7. Record: date, build number, device model, key prefix **redacted**, request
   id/timestamp from OpenRouter's activity page, screenshot filenames.

## Revocation

OpenRouter dashboard → Keys → **Delete/Disable** the key. The app then only
needs the key removed in AI Settings so the UI stops offering rewrite.

## What must not be claimed

* No claim that a live request succeeded until step 4 produced real wording
  from OpenRouter.
* No key value, partial key, or screenshot of the full key in any document.
* The feature must stay labelled **CODE-COMPLETE / LIVE PROVIDER
  DEMONSTRATION PENDING** in the requirements matrix until the owner records the
  evidence above.
