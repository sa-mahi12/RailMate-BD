// book-trip Edge Function — thin auth-validating wrapper around the
// service-role-only `book_trip_service` RPC. NOT DEPLOYED by workers;
// coordinator/owner deploys (see handoff A05 for exact command).
//
// Flow: Bearer JWT -> verified via publishable-key client auth.getUser() ->
// validate body -> if simulateSuccess=false return labelled failed simulation
// with ZERO writes -> else service-role client calls book_trip_service with
// the VERIFIED user id (never any owner id from the body).
// Secrets come only from hosted env (SUPABASE_URL / SUPABASE_ANON_KEY /
// SUPABASE_SERVICE_ROLE_KEY). Nothing is hardcoded or logged.

import { createClient } from "npm:@supabase/supabase-js@2";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SEAT_RE = /^[A-Z][0-9]{1,2}$/;
const MAX_BODY_BYTES = 16 * 1024;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 30;

// Best-effort per-user sliding-window limiter (single isolate only; the DB
// transaction remains the real atomicity guarantee, not this map).
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
  if (message.includes("SEAT_UNAVAILABLE") || message.includes("CONCURRENT_CONFLICT")) {
    return { status: 409, code: "SEAT_UNAVAILABLE" };
  }
  if (message.includes("TRIP_UNAVAILABLE")) return { status: 409, code: "TRIP_UNAVAILABLE" };
  if (message.includes("IDEMPOTENCY_CONFLICT")) return { status: 409, code: "IDEMPOTENCY_CONFLICT" };
  if (message.includes("ALREADY_CANCELLED")) return { status: 409, code: "ALREADY_CANCELLED" };
  if (
    message.includes("INVALID_") || message.includes("DUPLICATE_OR_INVALID_SEAT") ||
    message.includes("SEAT_UNKNOWN")
  ) {
    return { status: 400, code: "INVALID_REQUEST" };
  }
  return { status: 500, code: "BOOKING_FAILED" };
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

  let body: {
    trip_id?: unknown;
    request_id?: unknown;
    passengers?: unknown;
    seat_codes?: unknown;
    simulateSuccess?: unknown;
  };
  try {
    body = JSON.parse(raw);
  } catch {
    return json(400, { code: "INVALID_REQUEST" });
  }

  const tripId = body.trip_id;
  const requestId = body.request_id;
  const passengers = body.passengers;
  const seatCodes = body.seat_codes;
  const simulateSuccess = body.simulateSuccess;

  if (typeof tripId !== "string" || !UUID_RE.test(tripId)) {
    return json(400, { code: "INVALID_REQUEST" });
  }
  if (typeof requestId !== "string" || !UUID_RE.test(requestId)) {
    return json(400, { code: "INVALID_REQUEST" });
  }
  if (!Array.isArray(passengers) || passengers.length < 1 || passengers.length > 4) {
    return json(400, { code: "INVALID_REQUEST" });
  }
  for (const p of passengers) {
    const name = typeof p === "object" && p !== null
      ? String((p as Record<string, unknown>).name ?? "").trim()
      : "";
    if (name.length < 2 || name.length > 80) return json(400, { code: "INVALID_REQUEST" });
  }
  if (!Array.isArray(seatCodes) || seatCodes.length !== passengers.length) {
    return json(400, { code: "INVALID_REQUEST" });
  }
  const distinct = new Set(seatCodes);
  if (distinct.size !== seatCodes.length) return json(400, { code: "INVALID_REQUEST" });
  for (const s of seatCodes) {
    if (typeof s !== "string" || !SEAT_RE.test(s)) return json(400, { code: "INVALID_REQUEST" });
  }
  if (typeof simulateSuccess !== "boolean") return json(400, { code: "INVALID_REQUEST" });

  // Demo payment gate: failure path performs NO rpc and creates NO booking.
  if (!simulateSuccess) {
    return json(200, {
      status: "PAYMENT_SIMULATION_FAILED",
      detail: "DEMONSTRATION ONLY — no booking created, no charge.",
    });
  }

  const admin = createClient(url, serviceKey);
  const cleanPassengers = (passengers as Array<Record<string, unknown>>).map((p) => ({
    name: String(p.name).trim(),
  }));
  const { data, error } = await admin.rpc("book_trip_service", {
    p_user_id: userId,
    p_trip_id: tripId,
    p_request_id: requestId,
    p_passengers: cleanPassengers,
    p_seat_codes: seatCodes,
  });

  if (error) {
    const mapped = publicError(error.message ?? "");
    return json(mapped.status, { code: mapped.code });
  }
  // The returned uuid IS the booking id + reference (DEMONSTRATION ONLY ticket).
  return json(200, { booking_id: data, status: "CONFIRMED" });
});
