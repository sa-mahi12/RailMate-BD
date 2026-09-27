-- A05 atomic multi-seat booking — hardening layer on top of 20260927000003_booking_rpc.sql.
-- Status: DRAFT / NOT APPLIED. Coordinator applies in a disposable *hosted* staging project
-- first, runs the two-session concurrency proof, and only then stages to live.
-- Do NOT apply to a populated project without backup + separately logged review.
--
-- DESIGN CHOICE (deliberate, documented): EXTEND the existing service-role-only
-- `book_trip_service(...)` via CREATE OR REPLACE instead of adding the packet's
-- example `book_trip_seats(... auth.uid() ...)` SECURITY DEFINER variant.
-- Reasons:
--   1. Reviewed design (architecture/ATOMIC_BOOKING.md,
--      architecture/BOOKING_EDGE_FUNCTION_PSEUDOCODE.md) requires a
--      service-role-only RPC: the Edge Function verifies the Supabase JWT and
--      passes the *verified* user id as p_user_id. A second SECURITY DEFINER
--      entry point callable directly by any authenticated client would widen
--      the privileged write surface and contradict "No direct grant EXECUTE
--      to anon/authenticated".
--   2. Schema (20260927000001) keys idempotency as request_id uuid with
--      unique(user_id, request_id); a text idempotency key would need a schema
--      change, out of scope for this packet.
--   3. Schema bookings.status allows only ('CONFIRMED','CANCELLED'); there is
--      no pending-payment state. Simulate-failure never calls the RPC (Edge
--      returns a labelled failed simulation with zero writes), so the RPC only
--      ever inserts 'CONFIRMED'. The returned uuid IS the booking reference.
--
-- What this file does:
--   1. CREATE OR REPLACE book_trip_service (same signature) with the full
--      atomic transaction: validate -> serialize per-user -> idempotent replay
--      -> lock seat rows FOR UPDATE in sorted order -> insert booking +
--      passengers + seat links -> mark trip_seats -> verify row count.
--      Any failure RAISEs EXCEPTION; Postgres rolls back the whole transaction,
--      so overlapping requests never partially succeed.
--   2. CREATE OR REPLACE cancel_booking_service (same signature, whole-booking
--      cancel only; releases only seats still referencing this booking).
--   3. Revokes every direct client write path on bookings / booking_passengers
--      / booking_seats / trip_seats and restricts RPC EXECUTE to service_role.
-- Live ref psuzlyingfmstnyfvlnj — NO live SQL is run from this file by a worker.

-- ---------------------------------------------------------------------------
-- 1. Atomic booking RPC (service-role only; called by Edge after JWT verify).
-- ---------------------------------------------------------------------------
create or replace function public.book_trip_service(
  p_user_id uuid, p_trip_id uuid, p_request_id uuid,
  p_passengers jsonb, p_seat_codes text[]
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_n integer;
  v_distinct integer;
  v_count integer := 0;
  v_existing public.bookings%rowtype;
  v_booking_id uuid;
  v_fare integer;
  v_request_hash text;
  v_name text;
  v_code text;
  v_seat_id uuid;
  v_passenger_id uuid;
  v_i integer;
  v_row record;
begin
  if p_user_id is null or p_request_id is null or p_trip_id is null then
    raise exception 'INVALID_REQUEST';
  end if;
  if jsonb_typeof(p_passengers) is distinct from 'array' then
    raise exception 'INVALID_PASSENGERS';
  end if;
  v_n := jsonb_array_length(p_passengers);
  if v_n not between 1 and 4 or array_length(p_seat_codes,1) is distinct from v_n then
    raise exception 'INVALID_CAPACITY';
  end if;
  select count(distinct x) into v_distinct from unnest(p_seat_codes) as t(x);
  if v_distinct <> v_n or exists(select 1 from unnest(p_seat_codes) x where x is null or x !~ '^[A-Z][0-9]{1,2}$') then
    raise exception 'DUPLICATE_OR_INVALID_SEAT';
  end if;
  for v_i in 0..(v_n-1) loop
    v_name := trim(coalesce(p_passengers->v_i->>'name',''));
    if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_PASSENGER'; end if;
  end loop;
  -- Preserve seat/passenger order in fingerprint; idempotent retries compare the complete request.
  v_request_hash := md5(p_trip_id::text || '|' || p_passengers::text || '|' || p_seat_codes::text);
  -- Serialize the same owner's simultaneous requests before checking idempotency.
  -- Small academic scale: profile-row lock avoids a same-UUID race without an extra lock service.
  perform 1 from public.profiles where id=p_user_id for update;
  if not found then raise exception 'INVALID_USER'; end if;
  select * into v_existing from public.bookings
    where user_id=p_user_id and request_id=p_request_id for update;
  if found then
    if v_existing.request_fingerprint <> v_request_hash then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
    if v_existing.status = 'CANCELLED' then raise exception 'ALREADY_CANCELLED'; end if;
    return v_existing.id;
  end if;
  select fare_bdt into v_fare from public.trips
    where id=p_trip_id and active and departure_at>now() for share;
  if not found then raise exception 'TRIP_UNAVAILABLE'; end if;
  -- Lock actual seat rows in globally stable order (deadlock avoidance: never
  -- lock in request order). A loop counts ALL requested rows.
  for v_row in
    select id, seat_code, booking_id from public.trip_seats
      where trip_id=p_trip_id and seat_code=any(p_seat_codes)
      order by seat_code for update
  loop
    v_count := v_count+1;
    if v_row.booking_id is not null then raise exception 'SEAT_UNAVAILABLE'; end if;
  end loop;
  if v_count <> v_n then raise exception 'SEAT_UNKNOWN'; end if;
  insert into public.bookings (user_id,trip_id,request_id,request_fingerprint,status,total_fare_bdt)
    values (p_user_id,p_trip_id,p_request_id,v_request_hash,'CONFIRMED',v_n*v_fare)
    returning id into v_booking_id;
  for v_i in 1..v_n loop
    v_name := trim(p_passengers->(v_i-1)->>'name');
    v_code := p_seat_codes[v_i];
    insert into public.booking_passengers (booking_id,passenger_order,passenger_name)
      values (v_booking_id,v_i,v_name) returning id into v_passenger_id;
    select id into v_seat_id from public.trip_seats where trip_id=p_trip_id and seat_code=v_code;
    insert into public.booking_seats (booking_id,trip_seat_id,passenger_id)
      values (v_booking_id,v_seat_id,v_passenger_id);
  end loop;
  -- Conditional mark: succeeds only on still-unbooked rows; row_count mismatch
  -- raises and rolls back everything (defense in depth behind FOR UPDATE).
  update public.trip_seats set booking_id=v_booking_id
    where trip_id=p_trip_id and seat_code=any(p_seat_codes) and booking_id is null;
  get diagnostics v_count = row_count;
  if v_count <> v_n then raise exception 'CONCURRENT_CONFLICT'; end if;
  return v_booking_id;
end; $$;

comment on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) is
  'A05: atomic 1-4 seat booking. Service-role only; Edge passes JWT-verified user id. '
  'One transaction: FOR UPDATE seat locks in sorted order, idempotent on (user_id, request_id). '
  'Any seat conflict raises and rolls back all writes.';

-- ---------------------------------------------------------------------------
-- 2. Whole-booking cancellation (service-role only; owner checked inside).
-- ---------------------------------------------------------------------------
create or replace function public.cancel_booking_service(p_user_id uuid,p_booking_id uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
 v_booking public.bookings%rowtype;
begin
 select * into v_booking from public.bookings where id=p_booking_id and user_id=p_user_id for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if v_booking.status='CANCELLED' then return true; end if;
 update public.bookings set status='CANCELLED',cancelled_at=now() where id=p_booking_id;
 -- Releases only seats still referencing THIS booking; never another booking's seats.
 update public.trip_seats set booking_id=null where booking_id=p_booking_id;
 return true;
end; $$;

comment on function public.cancel_booking_service(uuid,uuid) is
  'A05: whole-booking cancel only (no partial cancel, no refund). Idempotent repeat returns true.';

-- ---------------------------------------------------------------------------
-- 3. Deny direct client writes: no anon/authenticated INSERT/UPDATE/DELETE on
--    bookings, booking_passengers, booking_seats, or trip_seats. Writes happen
--    only inside the service-role RPCs above. RLS denies by default when no
--    permissive write policy exists, so drop ANY such policy (guarded,
--    idempotent) and re-assert least-privilege grants. SELECT policies from
--    20260927000002_rls.sql are untouched.
-- ---------------------------------------------------------------------------
alter table public.bookings enable row level security;
alter table public.booking_passengers enable row level security;
alter table public.booking_seats enable row level security;
alter table public.trip_seats enable row level security;

do $$
declare r record;
begin
  for r in
    select tablename, policyname from pg_policies
      where schemaname = 'public'
        and tablename in ('bookings','booking_passengers','booking_seats','trip_seats')
        and cmd in ('INSERT','UPDATE','DELETE')
  loop
    execute format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, r.tablename);
  end loop;
end; $$;

revoke insert,update,delete on public.bookings,public.booking_passengers,public.booking_seats,public.trip_seats from anon,authenticated;

-- ---------------------------------------------------------------------------
-- 4. RPC execution: service_role ONLY. The Flutter client never calls these
--    functions directly; only the hosted book-trip Edge Function does.
-- ---------------------------------------------------------------------------
revoke all on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) from public,anon,authenticated;
grant execute on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) to service_role;
revoke all on function public.cancel_booking_service(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cancel_booking_service(uuid,uuid) to service_role;

-- Coordinator proof checklist (NOT run by worker; staging project only):
--   a. Two concurrent book_trip_service calls for the same seat -> exactly one
--      returns a uuid, the other raises SEAT_UNAVAILABLE or CONCURRENT_CONFLICT;
--      bookings count for that seat's trip increases by exactly one.
--   b. Multi-seat request with one conflicting seat -> exception, zero rows in
--      bookings/booking_passengers/booking_seats for that request_id, and all
--      requested seats keep their prior booking_id values (rollback proof).
--   c. Same (user_id, request_id) retried with identical body -> returns the
--      SAME booking id, no second booking row. Same key with different body ->
--      IDEMPOTENCY_CONFLICT.
--   d. Direct authenticated insert into bookings/trip_seats -> denied by RLS.
