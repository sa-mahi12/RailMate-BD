// cancel-booking Edge Function — thin auth-validating wrapper around the
// service-role-only `cancel_booking_service` RPC. NOT DEPLOYED by workers;
// coordinator/owner deploys.
//
// Flow: Bearer JWT -> verified via publishable-key client auth.getUser() ->
// validate body {booking_id} -> service-role client calls
// cancel_booking_service with the VERIFIED user id (never any owner id from
// the body). Whole-booking cancel only; idempotent repeat returns
// {status:"CANCELLED"}. Releases only seats still referencing THIS booking
// (server-side WHERE booking_id = p_booking_id); other seats untouched.
// Secrets come only from hosted env (SUPABASE_URL / SUPABASE_ANON_KEY /
// SUPABASE_SERVICE_ROLE_KEY). Nothing is hardcoded or logged.

import { createClient } from "npm:@supabase/supabase-js@2";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 4 * 1024;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 30;

// Best-effort per-user sliding-window limiter (single isolate only; the DB
// transaction remains the real correctness guarantee, not this map).
const hits = new Map<string, number[]>();

function rateLimited(userId: string): boolean {
  const now = Date.now();
  const arr = (hits.get(userId) ?? []).filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  arr.push(now);
  hits.set(userId, arr);
  return arr.length > RATE_LIMIT_MAX;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
    },
  });
}

// Map internal DB error strings to public codes without leaking SQL internals.
function publicError(message: string): { status: number; code: string } {
  if (message.includes("NOT_FOUND")) return { status: 404, code: "NOT_FOUND" };
  return { status: 500, code: "BOOKING_CANCEL_FAILED" };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json(204, {});
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anonKey || !serviceKey) {
    return json(500, { code: "SERVER_MISCONFIGURED" });
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json(401, { code: "UNAUTHORIZED" });

  // Verify JWT with the publishable-key client; never trust a body user id.
  const anon = createClient(url, anonKey);
  const { data: userData, error: userError } = await anon.auth.getUser(token);
  const userId = userData?.user?.id;
  if (userError || !userId) return json(401, { code: "UNAUTHORIZED" });

  if (rateLimited(userId)) return json(429, { code: "RATE_LIMITED" });

  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return json(400, { code: "INVALID_REQUEST" });
  }
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return json(413, { code: "BODY_TOO_LARGE" });

  let body: { booking_id?: unknown };
  try {
    body = JSON.parse(raw);
  } catch {
    return json(400, { code: "INVALID_REQUEST" });
  }

  const bookingId = body.booking_id;
  if (typeof bookingId !== "string" || !UUID_RE.test(bookingId)) {
    return json(400, { code: "INVALID_REQUEST" });
  }

  const admin = createClient(url, serviceKey);
  const { data, error } = await admin.rpc("cancel_booking_service", {
    p_user_id: userId,
    p_booking_id: bookingId,
  });

  if (error) {
    const mapped = publicError(error.message ?? "");
    return json(mapped.status, { code: mapped.code });
  }
  // `data` is true on first cancel AND on idempotent repeat (already
  // CANCELLED). DEMONSTRATION ONLY — no refund, no partial cancel.
  if (data !== true) return json(500, { code: "BOOKING_CANCEL_FAILED" });
  return json(200, { booking_id: bookingId, status: "CANCELLED" });
});
