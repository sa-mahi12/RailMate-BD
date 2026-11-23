// Tests for the pure Telegram verification state machine.
// Run: npx --yes deno@2 test supabase/functions/_shared/telegram_test.ts
//
// These tests drive MOCKED Telegram updates through the same code the webhook
// Edge Function runs. They prove the rules; they do NOT prove delivery from
// Telegram, which needs a configured bot (owner-side, see docs).

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type ChallengeRecord,
  maskPhone,
  normalizeSharedPhone,
  processUpdate,
  type TelegramContact,
  type TelegramUpdate,
  type WebhookDeps,
} from "./telegram.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const OTHER_USER = "22222222-2222-4222-8222-222222222222";
const TOKEN_HASH = "a".repeat(64);
const BOT = 900000001;
const T1 = 111;
const T2 = 222;

function challenge(over: Partial<ChallengeRecord> = {}): ChallengeRecord {
  return {
    id: "c0000000-0000-4000-8000-000000000001",
    user_id: USER,
    token_hash: TOKEN_HASH,
    status: "pending",
    telegram_user_id: null,
    expires_at: new Date(Date.now() + 5 * 60_000).toISOString(),
    ...over,
  };
}

interface Fake extends WebhookDeps {
  sent: { chatId: number; text: string; keyboard: boolean }[];
  verified: { challengeId: string; telegramUserId: number; phone: string }[];
  bound: { challengeId: string; telegramUserId: number }[];
  seen: Set<number>;
  completeUpdate(updateId: number): Promise<void>;
  releaseUpdate(updateId: number): Promise<void>;
}

function fakeDeps(over: Partial<WebhookDeps> = {}): Fake {
  const sent: Fake["sent"] = [];
  const verified: Fake["verified"] = [];
  const bound: Fake["bound"] = [];
  const seen = new Set<number>();
  return {
    sent,
    verified,
    bound,
    seen,
    now: () => new Date(),
    recordUpdate: async (id: number) => {
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    },
    completeUpdate: async () => {},
    releaseUpdate: async (id) => {
      seen.delete(id);
    },
    findChallengeByHash: async (_hash: string) => challenge(),
    findChallengeByTelegramUser: async (_id: number) =>
      challenge({ status: "contact_shared", telegram_user_id: _id }),
    bindTelegramUser: async (challengeId, telegramUserId) => {
      bound.push({ challengeId, telegramUserId });
      return true;
    },
    verifyContact: async (challengeId, telegramUserId, phone) => {
      verified.push({ challengeId, telegramUserId, phone });
      return "ok";
    },
    sendMessage: async (chatId, text, keyboard = false) => {
      sent.push({ chatId, text, keyboard });
    },
    ...over,
  };
}

function startUpdate(
  updateId: number,
  token = "tok_abcdefghijklmnop",
  from = T1,
): TelegramUpdate {
  return {
    update_id: updateId,
    message: {
      message_id: 10,
      date: 0,
      chat: { id: from, type: "private" },
      from: { id: from, is_bot: false },
      text: `/start ${token}`,
    },
  };
}

function contactUpdate(
  updateId: number,
  over: {
    from?: number;
    chatId?: number;
    chatType?: "private" | "group" | "supergroup";
    contactUserId?: number | null;
    phone?: string;
  } = {},
): TelegramUpdate {
  const from = over.from ?? T1;
  const contact: Record<string, unknown> = {
    phone_number: over.phone ?? "+8801712345678",
    first_name: "Probe",
  };
  if (over.contactUserId !== null) contact.user_id = over.contactUserId ?? from;
  return {
    update_id: updateId,
    message: {
      message_id: 11,
      date: 0,
      chat: { id: over.chatId ?? from, type: over.chatType ?? "private" },
      from: { id: from, is_bot: false },
      contact: contact as unknown as TelegramContact,
    },
  };
}

// 1. Successful Telegram contact sharing.
Deno.test("valid contact from the bound identity verifies the challenge", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  const result = await processUpdate(contactUpdate(1), deps);
  assertEquals(result, "verified");
  assertEquals(deps.verified.length, 1);
  assertEquals(deps.verified[0].phone, "+8801712345678");
  assert(deps.sent.some((m) => m.text.includes("verified")));
});

// 2. Invalid challenge.
Deno.test("unknown start token is rejected without binding", async () => {
  const deps = fakeDeps({ findChallengeByHash: async () => null });
  const result = await processUpdate(
    startUpdate(2, "nope_abcdefghijklmnop"),
    deps,
  );
  assertEquals(result, "rejected");
  assertEquals(deps.bound.length, 0);
  assert(deps.sent[0].text.toLowerCase().includes("expired"));
});

// 3. Expired challenge.
Deno.test("expired challenge is rejected and sends nothing secret", async () => {
  const deps = fakeDeps({
    findChallengeByHash: async () =>
      challenge({ expires_at: new Date(Date.now() - 1000).toISOString() }),
  });
  const result = await processUpdate(startUpdate(3), deps);
  assertEquals(result, "rejected");
  assertEquals(deps.bound.length, 0);
});

// 4. Reused challenge.
Deno.test("consumed challenge cannot be verified twice", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "verified", telegram_user_id: T1 }),
  });
  const result = await processUpdate(contactUpdate(4), deps);
  assertEquals(result, "rejected");
  assertEquals(deps.verified.length, 0);
});

// 5. Missing contact user id.
Deno.test("contact without user_id is not accepted as proof", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  const result = await processUpdate(
    contactUpdate(5, { contactUserId: null }),
    deps,
  );
  assertEquals(result, "rejected");
  assertEquals(deps.verified.length, 0);
});

// 6. Contact belonging to another Telegram user.
Deno.test("a contact card for somebody else is rejected", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  const result = await processUpdate(
    contactUpdate(6, { contactUserId: T2 }),
    deps,
  );
  assertEquals(result, "rejected");
  assertEquals(deps.verified.length, 0);
});

// 7. Group-chat contact sharing.
Deno.test("group chat contact sharing is rejected", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  const result = await processUpdate(
    contactUpdate(7, { chatType: "group", chatId: -100 }),
    deps,
  );
  assertEquals(result, "rejected");
  assertEquals(deps.verified.length, 0);
});

// 8. Challenge initiated by a different Telegram account.
Deno.test("another Telegram account cannot complete a bound challenge", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  const result = await processUpdate(contactUpdate(8, { from: T2 }), deps);
  assertEquals(result, "rejected");
  assertEquals(deps.verified.length, 0);
});

// 9. Duplicate webhook updates.
Deno.test("a repeated update_id is processed once", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  assertEquals(await processUpdate(contactUpdate(9), deps), "verified");
  assertEquals(await processUpdate(contactUpdate(9), deps), "duplicate");
  assertEquals(deps.verified.length, 1);
});

// 10. Multiple accounts attempting to bind the same Telegram identity.
Deno.test("a Telegram identity already linked to another account is refused", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
    verifyContact: async () => "conflict",
  });
  const result = await processUpdate(contactUpdate(10), deps);
  assertEquals(result, "rejected");
  assert(deps.sent.some((m) => m.text.toLowerCase().includes("already")));
});

// 11. Rate limiting (mocked at the persistence layer).
Deno.test("a rate-limited verification reports a retry message", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
    verifyContact: async () => "rate_limited",
  });
  const result = await processUpdate(contactUpdate(11), deps);
  assertEquals(result, "rejected");
  assert(deps.sent.some((m) => m.text.toLowerCase().includes("too many")));
});

// 12. Verification cancellation.
Deno.test("a cancelled challenge cannot be completed", async () => {
  const deps = fakeDeps({
    findChallengeByHash: async () => challenge({ status: "cancelled" }),
  });
  assertEquals(await processUpdate(startUpdate(12), deps), "rejected");
  assertEquals(deps.bound.length, 0);
});

Deno.test("a cancelled challenge rejects a late contact share", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "cancelled", telegram_user_id: T1 }),
  });
  assertEquals(await processUpdate(contactUpdate(13), deps), "rejected");
  assertEquals(deps.verified.length, 0);
});

// 13. Backend failure.
Deno.test("a database failure is reported politely, never as success", async () => {
  const deps = fakeDeps({
    findChallengeByHash: async () => {
      throw new Error("connection reset");
    },
  });
  const result = await processUpdate(startUpdate(14), deps);
  assertEquals(result, "error");
});

Deno.test("a failed verification write is not reported as verified", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
    verifyContact: async () => "not_found",
  });
  assertEquals(await processUpdate(contactUpdate(15), deps), "rejected");
  assert(!deps.sent.some((m) => m.text.includes("verified successfully")));
});

// Extra rules that protect the flow.
Deno.test("a typed phone number is never accepted as proof", async () => {
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () =>
      challenge({ status: "contact_shared", telegram_user_id: T1 }),
  });
  const update: TelegramUpdate = {
    update_id: 16,
    message: {
      message_id: 12,
      date: 0,
      chat: { id: T1, type: "private" },
      from: { id: T1, is_bot: false },
      text: "+8801712345678",
    },
  };
  assertEquals(await processUpdate(update, deps), "rejected");
  assertEquals(deps.verified.length, 0);
});

Deno.test("start binds only the first Telegram identity", async () => {
  const deps = fakeDeps({ bindTelegramUser: async () => false });
  assertEquals(
    await processUpdate(startUpdate(17, "tok_abcdefghijklmnop", T2), deps),
    "rejected",
  );
  assert(deps.sent.some((m) => m.text.toLowerCase().includes("different")));
});

Deno.test("the request_contact keyboard is sent on a valid start", async () => {
  const deps = fakeDeps();
  assertEquals(await processUpdate(startUpdate(18), deps), "started");
  assertEquals(deps.sent.length, 1);
  assertEquals(deps.sent[0].keyboard, true);
  assert(!deps.sent[0].text.includes("+880"));
});

Deno.test("a challenge belonging to a user is never echoed in chat", async () => {
  const deps = fakeDeps();
  await processUpdate(startUpdate(19), deps);
  assert(!deps.sent[0].text.includes(USER));
  assert(!deps.sent[0].text.includes(TOKEN_HASH));
});

Deno.test("normalizeSharedPhone keeps only real E.164 numbers", () => {
  assertEquals(normalizeSharedPhone("+8801712345678"), "+8801712345678");
  assertEquals(normalizeSharedPhone(" +880 1712-345678 "), "+8801712345678");
  assertEquals(normalizeSharedPhone("01712345678"), null);
  assertEquals(normalizeSharedPhone("+12"), null);
  assertEquals(normalizeSharedPhone(""), null);
  assertEquals(normalizeSharedPhone("+8801712345678901234"), null);
});

Deno.test("maskPhone never reveals the full number", () => {
  const masked = maskPhone("+8801712345678");
  assertEquals(masked.endsWith("5678"), true);
  assert(!masked.includes("17123456"));
  assert(masked.startsWith("+"));
});

Deno.test("a failed lookup can recover on redelivery of the same update", async () => {
  let fail = true;
  const deps = fakeDeps({
    findChallengeByHash: async () => {
      if (fail) throw new Error("temporary failure");
      return challenge();
    },
  });
  assertEquals(await processUpdate(startUpdate(30), deps), "error");
  fail = false;
  assertEquals(await processUpdate(startUpdate(30), deps), "started");
  assertEquals(deps.bound.length, 1);
  assertEquals(await processUpdate(startUpdate(30), deps), "duplicate");
});

Deno.test("a transient verification write error can recover on redelivery", async () => {
  let fail = true;
  const deps = fakeDeps({ verifyContact: async () => fail ? "error" : "ok" });
  assertEquals(await processUpdate(contactUpdate(31), deps), "error");
  fail = false;
  assertEquals(await processUpdate(contactUpdate(31), deps), "verified");
});

Deno.test("failed prompt delivery retries a binding owned by the same sender", async () => {
  const row = challenge();
  let fail = true;
  const deps = fakeDeps({
    findChallengeByHash: async () => row,
    bindTelegramUser: async (_id, user) => {
      row.telegram_user_id = user;
      row.status = "contact_shared";
      return true;
    },
    sendMessage: async (_id, _text, keyboard) => {
      if (fail && keyboard) throw new Error("temporary Telegram failure");
    },
  });
  assertEquals(await processUpdate(startUpdate(32), deps), "error");
  fail = false;
  assertEquals(await processUpdate(startUpdate(32), deps), "started");
  assertEquals(row.telegram_user_id, T1);
});

Deno.test("ledger acquisition failures return error rather than escaping", async () => {
  const deps = fakeDeps({
    recordUpdate: async () => {
      throw new Error("busy or offline");
    },
  });
  assertEquals(await processUpdate(startUpdate(33), deps), "error");
});

Deno.test("post-verification notification failure does not claim nothing was verified", async () => {
  const deps = fakeDeps({
    sendMessage: async () => {
      throw new Error("Telegram unavailable");
    },
  });
  assertEquals(await processUpdate(contactUpdate(34), deps), "verified");
  assertEquals(deps.verified.length, 1);
});

Deno.test("a consumed contact recovers when its completion acknowledgement fails", async () => {
  const row = {
    ...challenge({ status: "contact_shared", telegram_user_id: T1 }),
    verification_update_id: 35,
  };
  const deps = fakeDeps({
    findChallengeByTelegramUser: async () => row,
    verifyContact: async () => {
      row.status = "verified";
      return "ok";
    },
  });
  let fail = true;
  deps.completeUpdate = async () => {
    if (fail) throw new Error("completion unavailable");
  };
  assertEquals(await processUpdate(contactUpdate(35), deps), "error");
  fail = false;
  assertEquals(await processUpdate(contactUpdate(35), deps), "verified");
});

Deno.test("sender-owned digits-only international contact is canonicalized", async () => {
  const deps = fakeDeps();
  assertEquals(
    await processUpdate(contactUpdate(36, { phone: "8801712345678" }), deps),
    "verified",
  );
  assertEquals(deps.verified[0].phone, "+8801712345678");
});

Deno.test("typed digits-only international number is not contact proof", async () => {
  const deps = fakeDeps();
  const update = startUpdate(37);
  update.message!.text = "8801712345678";
  assertEquals(await processUpdate(update, deps), "rejected");
  assertEquals(deps.verified.length, 0);
});
