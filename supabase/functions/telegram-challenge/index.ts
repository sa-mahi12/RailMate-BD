// telegram-challenge Edge Function — creates and cancels a Telegram contact
// verification challenge for the signed-in user.
//
// NOT DEPLOYED by this session: deployment needs the owner's bot credentials
// and the Supabase access token (see docs/owner/telegram-setup.md).
//
// Flow: Bearer JWT -> verified with the publishable-key client -> the user id
// comes only from the verified session (never the body) -> a 32-byte random
// token is generated, only its SHA-256 is stored, the plaintext token goes
// into the t.me deep link and nowhere else.
//
// Secrets (hosted env only): SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY, TELEGRAM_BOT_USERNAME. The bot token is NOT
// needed here and is never sent to the client.

import { createClient } from "npm:@supabase/supabase-js@2";
import { sha256Hex } from "../_shared/telegram.ts";

const CHALLENGE_TTL_MS = 5 * 60_000;
const RATE_WINDOW_MS = 10 * 60_000;
const RATE_MAX = 5;
const MAX_BODY_BYTES = 4 * 1024;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
      "cache-control": "no-store",
    },
  });
}

/** URL-safe base64 without padding (Telegram start payload charset). */
function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json(204, {});
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const botUsername = (Deno.env.get("TELEGRAM_BOT_USERNAME") ?? "").replace(/^@/, "");
  if (!url || !anonKey || !serviceKey) {
    return json(500, { code: "SERVER_MISCONFIGURED" });
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json(401, { code: "UNAUTHORIZED" });

  const anon = createClient(url, anonKey);
  const { data: userData, error: userError } = await anon.auth.getUser(token);
  const userId = userData?.user?.id;
  if (userError || !userId) return json(401, { code: "UNAUTHORIZED" });

  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return json(413, { code: "BODY_TOO_LARGE" });

  let action = "create";
  if (raw.trim().length > 0) {
    try {
      const body = JSON.parse(raw) as { action?: unknown };
      if (typeof body.action === "string") action = body.action;
    } catch {
      return json(400, { code: "INVALID_REQUEST" });
    }
  }
  if (action !== "create" && action !== "cancel") {
    return json(400, { code: "INVALID_REQUEST" });
  }

  const admin = createClient(url, serviceKey);
  const now = new Date();

  if (action === "cancel") {
    // Cancellation is scoped to the caller and never touches a verified row.
    const { data, error } = await admin
      .from("phone_verifications")
      .update({ status: "cancelled", cancelled_at: now.toISOString() })
      .eq("user_id", userId)
      .in("status", ["pending", "contact_shared"])
      .select("id");
    if (error) return json(500, { code: "CANCEL_FAILED" });
    return json(200, { cancelled: (data ?? []).length });
  }

  // The bot username is public, but without it no deep link can be built.
  if (!botUsername) return json(503, { code: "TELEGRAM_NOT_CONFIGURED" });

  const since = new Date(now.getTime() - RATE_WINDOW_MS).toISOString();
  const { count, error: countError } = await admin
    .from("phone_verifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", since);
  if (countError) return json(500, { code: "CHALLENGE_FAILED" });
  if ((count ?? 0) >= RATE_MAX) return json(429, { code: "RATE_LIMITED" });

  // Expire stale rows, then cancel any still-active challenge: the partial
  // unique index allows exactly one active challenge per user.
  await admin
    .from("phone_verifications")
    .update({ status: "expired" })
    .eq("user_id", userId)
    .in("status", ["pending", "contact_shared"])
    .lte("expires_at", now.toISOString());
  await admin
    .from("phone_verifications")
    .update({ status: "cancelled", cancelled_at: now.toISOString() })
    .eq("user_id", userId)
    .in("status", ["pending", "contact_shared"]);

  const secret = randomToken();
  const expiresAt = new Date(now.getTime() + CHALLENGE_TTL_MS).toISOString();
  const { data: inserted, error: insertError } = await admin
    .from("phone_verifications")
    .insert({
      user_id: userId,
      token_hash: await sha256Hex(secret),
      status: "pending",
      method: "telegram_contact",
      expires_at: expiresAt,
    })
    .select("id, expires_at")
    .single();
  if (insertError || !inserted) {
    return json(500, { code: "CHALLENGE_FAILED" });
  }

  // The deep link carries only the random token; no user id, no phone number.
  return json(200, {
    challenge_id: inserted.id,
    deep_link: `https://t.me/${botUsername}?start=${secret}`,
    expires_at: inserted.expires_at,
  });
});
