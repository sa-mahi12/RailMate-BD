-- P41 — Telegram contact phone verification (RailMate BD)
--
-- Scope: additive only. Nothing here touches auth.users, profiles, bookings or
-- the SMS phone lane. No SMS is sent, and `auth.users.phone_confirmed_at` is
-- deliberately never written: this is a Telegram contact check, recorded with
-- method = 'telegram_contact'.
--
-- Writes are service-role only (the Edge Functions). The app may read its own
-- rows so it can show the challenge state and the masked number.

create table if not exists public.phone_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- SHA-256 hex of the random start token. The plaintext token only ever
  -- exists inside the Telegram deep link.
  token_hash text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'contact_shared', 'verified', 'expired', 'cancelled')),
  method text not null default 'telegram_contact'
    check (method = 'telegram_contact'),
  telegram_user_id bigint,
  phone_e164 text,
  phone_masked text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  bound_at timestamptz,
  verified_at timestamptz,
  consumed_at timestamptz,
  cancelled_at timestamptz,
  constraint phone_verifications_e164_format
    check (phone_e164 is null or phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  constraint phone_verifications_verified_has_phone
    check (status <> 'verified' or (phone_e164 is not null and verified_at is not null))
);

comment on table public.phone_verifications is
  'Telegram contact verification challenges. Method is always telegram_contact; this is not Supabase SMS OTP and never sets auth.users.phone_confirmed_at.';

-- One active challenge per user: a second create cancels the first.
create unique index if not exists phone_verifications_one_active_per_user
  on public.phone_verifications (user_id)
  where status in ('pending', 'contact_shared');

-- One Telegram identity may only ever be linked to one RailMate account.
create unique index if not exists phone_verifications_telegram_identity_once
  on public.phone_verifications (telegram_user_id)
  where status = 'verified';

create index if not exists phone_verifications_user_created_idx
  on public.phone_verifications (user_id, created_at desc);

create index if not exists phone_verifications_expiry_idx
  on public.phone_verifications (expires_at)
  where status in ('pending', 'contact_shared');

-- Webhook idempotency: a repeated Telegram update_id is processed once.
create table if not exists public.telegram_webhook_updates (
  update_id bigint primary key,
  received_at timestamptz not null default now()
);

comment on table public.telegram_webhook_updates is
  'Idempotency ledger for Telegram webhook updates (service-role access only).';

alter table public.phone_verifications enable row level security;
alter table public.telegram_webhook_updates enable row level security;

-- Read-own only. There are deliberately no insert/update/delete policies:
-- clients cannot mint, rebind or verify a challenge themselves.
drop policy if exists phone_verifications_select_own on public.phone_verifications;
create policy phone_verifications_select_own
  on public.phone_verifications
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on public.telegram_webhook_updates from anon, authenticated;

grant select on public.phone_verifications to authenticated;
