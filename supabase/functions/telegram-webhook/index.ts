// telegram-webhook Edge Function — Telegram Bot API update receiver.
//
// NOT DEPLOYED by this session: deployment needs the owner's bot token and
// webhook secret (see docs/owner/telegram-setup.md).
//
// Every rule lives in ../_shared/telegram.ts so the same logic is covered by
// mocked-update tests (supabase/functions/_shared/telegram_test.ts); this
// file only provides the database and Telegram adapters.
//
// Secrets (hosted env only): TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET,
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Nothing is logged: no token, no
// phone number, no challenge plaintext.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  type ChallengeRecord,
  maskPhone,
  processUpdate,
  type TelegramUpdate,
  type VerifyOutcome,
  type WebhookDeps,
} from "../_shared/telegram.ts";

const RATE_WINDOW_MS = 60 * 60_000;
const RATE_MAX_VERIFICATIONS = 10;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

type Row = {
  id: string;
  user_id: string;
  token_hash: string;
  status: ChallengeRecord["status"];
  telegram_user_id: number | null;
  expires_at: string;
  verification_update_id: number | null;
};

function toChallenge(row: Row | null): ChallengeRecord | null {
  if (!row) return null;
  return {
    id: row.id,
    user_id: row.user_id,
    token_hash: row.token_hash,
    status: row.status,
    telegram_user_id: row.telegram_user_id,
    expires_at: row.expires_at,
    verification_update_id: row.verification_update_id,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
  const webhookSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  if (!url || !serviceKey || !botToken || !webhookSecret) {
    return json(500, { code: "SERVER_MISCONFIGURED" });
  }

  const presented = req.headers.get("x-telegram-bot-api-secret-token") ?? "";
  if (!timingSafeEqual(presented, webhookSecret)) {
    // Telegram is the only caller; anything else is refused outright.
    return json(401, { code: "UNAUTHORIZED" });
  }

  let update: TelegramUpdate;
  try {
    update = (await req.json()) as TelegramUpdate;
  } catch {
    return json(400, { code: "INVALID_UPDATE" });
  }
  if (typeof update?.update_id !== "number") {
    return json(400, { code: "INVALID_UPDATE" });
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) =>
        fetch(input, {
          ...init,
          signal: AbortSignal.timeout(10_000),
        }),
    },
  });
  const claimId = crypto.randomUUID();

  const deps: WebhookDeps = {
    now: () => new Date(),

    recordUpdate: async (updateId: number) => {
      const now = new Date();
      const lease = {
        claim_id: claimId,
        lease_expires_at: new Date(now.getTime() + 120_000).toISOString(),
      };
      const { data, error } = await admin
        .from("telegram_webhook_updates")
        .insert({ update_id: updateId, state: "processing", ...lease })
        .select("update_id");
      if (error) {
        if ((error as { code?: string }).code !== "23505") {
          throw new Error("update record failed");
        }
        const { data: existing, error: lookupError } = await admin
          .from("telegram_webhook_updates").select("state")
          .eq("update_id", updateId).maybeSingle();
        if (lookupError) throw new Error("update lookup failed");
        if (existing?.state === "completed") return false;
        const { data: reclaimed, error: reclaimError } = await admin
          .from("telegram_webhook_updates").update(lease)
          .eq("update_id", updateId).eq("state", "processing")
          .lte("lease_expires_at", now.toISOString()).select("update_id");
        if (reclaimError || !(reclaimed ?? []).length) {
          throw new Error("update busy or reclaim failed");
        }
        return true;
      }
      return (data ?? []).length > 0;
    },

    completeUpdate: async (updateId) => {
      const { data, error } = await admin.from("telegram_webhook_updates")
        .update({ state: "completed", completed_at: new Date().toISOString() })
        .eq("update_id", updateId).eq("claim_id", claimId)
        .eq("state", "processing").select("update_id");
      if (error || !(data ?? []).length) {
        throw new Error("update completion failed");
      }
    },

    releaseUpdate: async (updateId) => {
      const { error } = await admin.from("telegram_webhook_updates").delete()
        .eq("update_id", updateId).eq("claim_id", claimId).eq(
          "state",
          "processing",
        );
      if (error) throw new Error("update release failed");
    },

    findChallengeByHash: async (tokenHash: string) => {
      const { data, error } = await admin
        .from("phone_verifications")
        .select(
          "id,user_id,token_hash,status,telegram_user_id,expires_at,verification_update_id",
        )
        .eq("token_hash", tokenHash)
        .maybeSingle();
      if (error) throw new Error("challenge lookup failed");
      return toChallenge(data as Row | null);
    },

    findChallengeByTelegramUser: async (telegramUserId: number) => {
      const { data, error } = await admin
        .from("phone_verifications")
        .select(
          "id,user_id,token_hash,status,telegram_user_id,expires_at,verification_update_id",
        )
        .eq("telegram_user_id", telegramUserId)
        .in("status", ["pending", "contact_shared", "verified", "cancelled"])
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw new Error("challenge lookup failed");
      return toChallenge(data as Row | null);
    },

    bindTelegramUser: async (challengeId: string, telegramUserId: number) => {
      const nowIso = new Date().toISOString();
      const { data, error } = await admin
        .from("phone_verifications")
        .update({
          telegram_user_id: telegramUserId,
          status: "contact_shared",
          bound_at: nowIso,
        })
        .eq("id", challengeId)
        .is("telegram_user_id", null)
        .eq("status", "pending")
        .gt("expires_at", nowIso)
        .select("id");
      if (error) throw new Error("bind failed");
      return (data ?? []).length > 0;
    },

    verifyContact: async (
      challengeId: string,
      telegramUserId: number,
      phoneE164: string,
      updateId: number,
    ): Promise<VerifyOutcome> => {
      const since = new Date(Date.now() - RATE_WINDOW_MS).toISOString();
      const { count, error: countError } = await admin
        .from("phone_verifications")
        .select("id", { count: "exact", head: true })
        .eq("telegram_user_id", telegramUserId)
        .eq("status", "verified")
        .gte("verified_at", since);
      if (countError) return "error";
      if ((count ?? 0) >= RATE_MAX_VERIFICATIONS) return "rate_limited";

      const nowIso = new Date().toISOString();
      const { data, error } = await admin
        .from("phone_verifications")
        .update({
          status: "verified",
          phone_e164: phoneE164,
          phone_masked: maskPhone(phoneE164),
          verified_at: nowIso,
          consumed_at: nowIso,
          method: "telegram_contact",
          verification_update_id: updateId,
        })
        .eq("id", challengeId)
        .eq("telegram_user_id", telegramUserId)
        .in("status", ["pending", "contact_shared"])
        .gt("expires_at", nowIso)
        .is("consumed_at", null)
        .select("id");
      if (error) {
        // 23505 = the partial unique index on a verified telegram identity.
        if ((error as { code?: string }).code === "23505") return "conflict";
        return "error";
      }
      return (data ?? []).length > 0 ? "ok" : "not_found";
    },

    sendMessage: async (chatId: number, text: string, keyboard = false) => {
      const payload: Record<string, unknown> = {
        chat_id: chatId,
        text,
        disable_web_page_preview: true,
      };
      if (keyboard) {
        payload.reply_markup = {
          keyboard: [
            [{ text: "Share my phone number", request_contact: true }],
          ],
          resize_keyboard: true,
          one_time_keyboard: true,
        };
      }
      const resp = await fetch(
        `https://api.telegram.org/bot${botToken}/sendMessage`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!resp.ok) throw new Error("telegram send failed");
    },
  };

  const result = await processUpdate(update, deps);
  // Completed/rejected updates are acknowledged; transient failures and
  // in-flight claims get non-2xx so Telegram can redeliver safely.
  return json(result === "error" ? 503 : 200, {
    ok: result !== "error",
    result,
  });
});
