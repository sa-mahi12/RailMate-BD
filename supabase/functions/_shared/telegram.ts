// Pure Telegram verification state machine (RailMate BD).
//
// Shared by the `telegram-webhook` Edge Function and its Deno tests. Nothing
// here touches the network or the database: every side effect goes through
// [WebhookDeps], so the rules can be tested with mocked Telegram updates.
//
// The rules, in order: only private chats where chat.id === from.id count; a
// contact card must belong to the sender; the challenge must exist, be
// unexpired, unconsumed and bound to the same Telegram user; and one Telegram
// identity may only ever be linked to one RailMate account.
//
// NOTE: this is *not* Supabase SMS OTP. Nothing here sets `phone_confirmed_at`
// and no SMS is sent or claimed.

/** Lifecycle of one verification challenge row. */
export type ChallengeStatus =
  | "pending"
  | "contact_shared"
  | "verified"
  | "expired"
  | "cancelled";

/** The subset of a challenge row the state machine needs. */
export interface ChallengeRecord {
  id: string;
  user_id: string;
  token_hash: string;
  status: ChallengeStatus;
  telegram_user_id: number | null;
  expires_at: string;
}

export interface TelegramContact {
  phone_number: string;
  user_id?: number;
  first_name?: string;
}

export interface TelegramMessage {
  message_id: number;
  date: number;
  chat: { id: number; type: string };
  from?: { id: number; is_bot?: boolean };
  text?: string;
  contact?: TelegramContact;
}

export interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
}

/** Result of atomically consuming a challenge. */
export type VerifyOutcome =
  | "ok"
  | "not_found"
  | "conflict"
  | "rate_limited"
  | "error";

export interface WebhookDeps {
  now(): Date;
  /** Inserts the Telegram update id; false when it was already processed. */
  recordUpdate(updateId: number): Promise<boolean>;
  /** Looks a challenge up by the SHA-256 hex of its start token. */
  findChallengeByHash(tokenHash: string): Promise<ChallengeRecord | null>;
  /** Looks the active challenge bound to a Telegram user, if any. */
  findChallengeByTelegramUser(
    telegramUserId: number,
  ): Promise<ChallengeRecord | null>;
  /** Binds the first Telegram identity to the challenge; false if taken. */
  bindTelegramUser(
    challengeId: string,
    telegramUserId: number,
  ): Promise<boolean>;
  /** Atomically consumes the challenge and stores the verified number. */
  verifyContact(
    challengeId: string,
    telegramUserId: number,
    phoneE164: string,
  ): Promise<VerifyOutcome>;
  sendMessage(
    chatId: number,
    text: string,
    keyboard?: boolean,
  ): Promise<void>;
}

export type ProcessResult =
  | "ignored"
  | "duplicate"
  | "started"
  | "verified"
  | "rejected"
  | "error";

export const START_PROMPT =
  "RailMate BD phone verification.\n\n" +
  "We ask for your phone number only to show a verified contact on your " +
  "RailMate BD account. Your number is stored masked and is never shown to " +
  "other travellers.\n\n" +
  "Tap the button below to share your own number with the bot.";

export const VERIFIED_TEXT =
  "Your phone number is verified successfully. Return to the RailMate BD app " +
  "to see it on your profile. DEMONSTRATION ONLY — this is not an SMS check.";

export const EXPIRED_TEXT =
  "This verification link has expired or is not valid. Open the RailMate BD " +
  "app and tap Verify with Telegram again.";

export const DIFFERENT_ACCOUNT_TEXT =
  "This verification link is already being used by a different Telegram " +
  "account. Open RailMate BD and start a new verification.";

export const ALREADY_LINKED_TEXT =
  "This Telegram account is already linked to another RailMate BD account. " +
  "Sign in to that account, or contact support if this is unexpected.";

export const RATE_LIMITED_TEXT =
  "Too many verification attempts. Wait a few minutes and try again from the " +
  "RailMate BD app.";

export const WRONG_CONTACT_TEXT =
  "We could not verify that contact. Share your own number with the button in " +
  "this private chat — typing a number is not accepted as proof.";

export const PRIVATE_ONLY_TEXT =
  "For privacy, phone verification only works in a private chat with this " +
  "bot.";

export const TYPED_NUMBER_TEXT =
  "Typing a number is not accepted as proof. Use the Share phone number " +
  "button in this chat.";

export const GENERIC_ERROR_TEXT =
  "Something went wrong on our side. Nothing was verified. Please try again " +
  "from the RailMate BD app.";

const E164 = /^\+[1-9]\d{7,14}$/;

/** Trims and strips separators, then accepts only a well-formed E.164 value. */
export function normalizeSharedPhone(raw: string): string | null {
  if (typeof raw !== "string") return null;
  const cleaned = raw.replace(/[\s()\-.]/g, "").trim();
  return E164.test(cleaned) ? cleaned : null;
}

/** Masks all but the country prefix and last four digits. */
export function maskPhone(e164: string): string {
  if (!E164.test(e164)) return "hidden";
  const tail = e164.slice(-4);
  const head = e164.slice(0, Math.max(2, e164.length - 10));
  return `${head}${"*".repeat(Math.max(3, e164.length - head.length - 4))}${tail}`;
}

/** SHA-256 hex of a challenge token (Web Crypto, no dependencies). */
export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function isExpired(challenge: ChallengeRecord, now: Date): boolean {
  const at = Date.parse(challenge.expires_at);
  return Number.isNaN(at) || at <= now.getTime();
}

/** Extracts the token from `/start <token>` (also `/start@bot <token>`). */
export function startToken(text: string | undefined): string | null {
  if (!text) return null;
  const match = /^\/start(?:@[A-Za-z0-9_]+)?(?:\s+(\S+))?\s*$/.exec(text.trim());
  if (!match) return null;
  const token = match[1] ?? "";
  return /^[A-Za-z0-9_-]{16,128}$/.test(token) ? token : null;
}

export async function processUpdate(
  update: TelegramUpdate,
  deps: WebhookDeps,
): Promise<ProcessResult> {
  const message = update.message;
  if (!message) return "ignored";

  const fromId = message.from?.id;
  if (!fromId) return "ignored";

  const fresh = await deps.recordUpdate(update.update_id);
  if (!fresh) return "duplicate";

  try {
    if (message.chat.type !== "private" || message.chat.id !== fromId) {
      // Never echo anything into a group.
      if (message.chat.type === "private") {
        await deps.sendMessage(message.chat.id, PRIVATE_ONLY_TEXT);
      }
      return "rejected";
    }

    if (message.contact) {
      return await handleContact(message, fromId, deps);
    }

    if (typeof message.text === "string") {
      const token = startToken(message.text);
      if (token) return await handleStart(message, fromId, token, deps);
      if (E164.test(message.text.replace(/[\s()\-.]/g, ""))) {
        await deps.sendMessage(message.chat.id, TYPED_NUMBER_TEXT, true);
        return "rejected";
      }
    }
    return "ignored";
  } catch (_err) {
    // A database or Telegram failure must never look like a success.
    try {
      await deps.sendMessage(message.chat.id, GENERIC_ERROR_TEXT);
    } catch (_ignored) {
      // Best effort only.
    }
    return "error";
  }
}

async function handleStart(
  message: TelegramMessage,
  fromId: number,
  token: string,
  deps: WebhookDeps,
): Promise<ProcessResult> {
  const hash = await sha256Hex(token);
  const challenge = await deps.findChallengeByHash(hash);
  if (!challenge) {
    await deps.sendMessage(message.chat.id, EXPIRED_TEXT);
    return "rejected";
  }
  if (challenge.status !== "pending") {
    await deps.sendMessage(
      message.chat.id,
      challenge.status === "cancelled" ? EXPIRED_TEXT : DIFFERENT_ACCOUNT_TEXT,
    );
    return "rejected";
  }
  if (isExpired(challenge, deps.now())) {
    await deps.sendMessage(message.chat.id, EXPIRED_TEXT);
    return "rejected";
  }
  const bound = await deps.bindTelegramUser(challenge.id, fromId);
  if (!bound) {
    await deps.sendMessage(message.chat.id, DIFFERENT_ACCOUNT_TEXT);
    return "rejected";
  }
  await deps.sendMessage(message.chat.id, START_PROMPT, true);
  return "started";
}

async function handleContact(
  message: TelegramMessage,
  fromId: number,
  deps: WebhookDeps,
): Promise<ProcessResult> {
  const contact = message.contact!;

  // The card must describe the sender, not somebody in their address book.
  if (typeof contact.user_id !== "number" || contact.user_id !== fromId) {
    await deps.sendMessage(message.chat.id, WRONG_CONTACT_TEXT, true);
    return "rejected";
  }

  const phone = normalizeSharedPhone(contact.phone_number ?? "");
  if (!phone) {
    await deps.sendMessage(message.chat.id, WRONG_CONTACT_TEXT, true);
    return "rejected";
  }

  const challenge = await deps.findChallengeByTelegramUser(fromId);
  if (
    !challenge ||
    challenge.status === "verified" ||
    challenge.status === "cancelled" ||
    challenge.status === "expired"
  ) {
    await deps.sendMessage(message.chat.id, EXPIRED_TEXT);
    return "rejected";
  }
  if (challenge.telegram_user_id !== null && challenge.telegram_user_id !== fromId) {
    await deps.sendMessage(message.chat.id, DIFFERENT_ACCOUNT_TEXT);
    return "rejected";
  }
  if (isExpired(challenge, deps.now())) {
    await deps.sendMessage(message.chat.id, EXPIRED_TEXT);
    return "rejected";
  }

  const outcome = await deps.verifyContact(challenge.id, fromId, phone);
  switch (outcome) {
    case "ok":
      await deps.sendMessage(message.chat.id, VERIFIED_TEXT);
      return "verified";
    case "conflict":
      await deps.sendMessage(message.chat.id, ALREADY_LINKED_TEXT);
      return "rejected";
    case "rate_limited":
      await deps.sendMessage(message.chat.id, RATE_LIMITED_TEXT);
      return "rejected";
    case "not_found":
      await deps.sendMessage(message.chat.id, EXPIRED_TEXT);
      return "rejected";
    case "error":
    default:
      await deps.sendMessage(message.chat.id, GENERIC_ERROR_TEXT);
      return "error";
  }
}
