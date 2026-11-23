// Executes the actual Edge handler with HTTP/storage boundaries mocked.
// No hosted Supabase, Telegram call, credential or migration is used.
import { assertEquals } from "jsr:@std/assert@1";

let handler: (request: Request) => Promise<Response>;
const testEnvironment: Record<string, string> = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "test-only-key",
  TELEGRAM_BOT_TOKEN: "test-only-bot",
  TELEGRAM_WEBHOOK_SECRET: "test-only-header",
};
const originalServe = Deno.serve;
const originalGet = Deno.env.get;
try {
  Deno.serve = ((callback: typeof handler) => {
    handler = callback;
  }) as typeof Deno.serve;
  Deno.env.get = (name: string) => testEnvironment[name];
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
  Deno.env.get = originalGet;
}

Deno.test("actual webhook sends retryable HTTP failure after a transient lookup error", async () => {
  const originalFetch = globalThis.fetch;
  const originalGet = Deno.env.get;
  Deno.env.get = (name: string) => testEnvironment[name];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url.includes("/phone_verifications")) {
      return new Response(
        JSON.stringify({ code: "XX000", message: "temporary failure" }),
        { status: 500 },
      );
    }
    if (url.includes("/telegram_webhook_updates")) {
      return new Response(JSON.stringify([{ update_id: 40 }]), { status: 201 });
    }
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  }) as typeof fetch;
  try {
    const response = await handler(
      new Request("https://example.invalid/webhook", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-telegram-bot-api-secret-token": "test-only-header",
        },
        body: JSON.stringify({
          update_id: 40,
          message: {
            message_id: 1,
            date: 0,
            from: { id: 111 },
            chat: { id: 111, type: "private" },
            text: "/start tok_abcdefghijklmnop",
          },
        }),
      }),
    );
    assertEquals(response.status, 503);
    assertEquals(await response.json(), { ok: false, result: "error" });
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalGet;
  }
});

for (const state of ["completed", "busy", "expired"] as const) {
  Deno.test(`actual webhook ${state} claim respects completion/lease ownership`, async () => {
    const originalFetch = globalThis.fetch;
    const originalGet = Deno.env.get;
    Deno.env.get = (name) => testEnvironment[name];
    let effects = 0;
    let reclaimCalls = 0;
    let completionCalls = 0;
    let claimId = "";
    globalThis.fetch =
      (async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = new URL(String(input));
        const method = init?.method ?? "GET";
        if (url.pathname.endsWith("/telegram_webhook_updates")) {
          if (method === "POST") {
            claimId = JSON.parse(String(init?.body)).claim_id;
            return new Response(JSON.stringify({ code: "23505" }), {
              status: 409,
            });
          }
          if (method === "GET") {
            return new Response(
              JSON.stringify([{
                state: state === "completed" ? "completed" : "processing",
              }]),
            );
          }
          if (method === "PATCH") {
            const body = JSON.parse(String(init?.body));
            assertEquals(url.searchParams.get("state"), "eq.processing");
            assertEquals(url.searchParams.get("update_id"), "eq.41");
            if (body.state === "completed") {
              completionCalls++;
              assertEquals(url.searchParams.get("claim_id"), `eq.${claimId}`);
              return new Response(JSON.stringify([{ update_id: 41 }]));
            }
            reclaimCalls++;
            assertEquals(body.claim_id, claimId);
            assertEquals(
              url.searchParams.get("lease_expires_at")?.startsWith("lte."),
              true,
            );
            return new Response(
              JSON.stringify(state === "expired" ? [{ update_id: 41 }] : []),
            );
          }
        }
        effects++;
        if (url.pathname.endsWith("/phone_verifications")) {
          return new Response("[]");
        }
        return new Response(JSON.stringify({ ok: true }));
      }) as typeof fetch;
    try {
      const response = await handler(
        new Request("https://example.invalid/webhook", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-telegram-bot-api-secret-token": "test-only-header",
          },
          body: JSON.stringify({
            update_id: 41,
            message: {
              message_id: 1,
              date: 0,
              from: { id: 111 },
              chat: { id: 111, type: "private" },
              text: "/start tok_abcdefghijklmnop",
            },
          }),
        }),
      );
      assertEquals(response.status, state === "busy" ? 503 : 200);
      assertEquals(
        (await response.json()).result,
        state === "completed"
          ? "duplicate"
          : state === "busy"
          ? "error"
          : "rejected",
      );
      assertEquals(reclaimCalls, state === "completed" ? 0 : 1);
      assertEquals(completionCalls, state === "expired" ? 1 : 0);
      assertEquals(effects, state === "expired" ? 2 : 0);
    } finally {
      globalThis.fetch = originalFetch;
      Deno.env.get = originalGet;
    }
  });
}
