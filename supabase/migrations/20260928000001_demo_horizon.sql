-- F05 — dynamic daily demo horizon (coordinator-reviewed, worker-B draft).
-- Applies AFTER 20260927000001_initial_schema.sql (+ RLS 000002,
-- booking RPC 000003/00063000, graphql 00062800). All statements are
-- IF NOT EXISTS / ON CONFLICT / CREATE OR REPLACE guarded; re-runnable.
-- DEMONSTRATION ONLY — synthetic timetable/fares/occupancy, NOT real
-- railway data. Every generated train_name carries "(Demo)"; all ticket
-- artifacts must keep stating DEMONSTRATION ONLY.
--
-- What this file does (new objects only, except §6 RPC correction):
--   1. Upserts the 8 demo stations by code (existing DAC/CGP/SYL/RJH ids
--      from 20260927000005_demo_seed.sql stay stable; adds AIR/CML/FEN/KHL).
--   2. Adds trips.demo_key + partial unique index (idempotency key).
--   3. Adds trip_seats.demo_reserved (deterministic demo hold flag).
--   4. Creates owner/admin refresh_demo_horizon() for today..+20d trips +
--      A1-D10 seats each with deterministic occupancy. NEVER overwrites
--      booking_id; NEVER granted to anon/authenticated.
--   5. CORRECTS book_trip_service (CREATE OR REPLACE, behavior otherwise
--      identical to 20260927063000_booking_atomic.sql): a seat is
--      unavailable when booking_id IS NOT NULL OR demo_reserved IS TRUE.

-- ---------------------------------------------------------------------------
-- 1. Stations: 8 demo stations, upsert by code, existing ids stable.
--    (id is never in the SET clause, so the 4 seeded rows keep their ids.)
-- ---------------------------------------------------------------------------
insert into public.stations (id, code, name, latitude, longitude)
values
  ('11111111-1111-4111-8111-111111111111', 'DAC', 'Dhaka',         23.810300, 90.412500),
  ('55555555-5555-4555-8555-555555555555', 'AIR', 'Dhaka Airport', 23.843100, 90.397300),
  ('66666666-6666-4666-8666-666666666666', 'CML', 'Cumilla',       23.460700, 91.180900),
  ('77777777-7777-4777-8777-777777777777', 'FEN', 'Feni',          23.023500, 91.384100),
  ('22222222-2222-4222-8222-222222222222', 'CGP', 'Chattogram',    22.356900, 91.783200),
  ('33333333-3333-4333-8333-333333333333', 'SYL', 'Sylhet',        24.894900, 91.869200),
  ('44444444-4444-4444-8444-444444444444', 'RJH', 'Rajshahi',      24.374500, 88.604200),
  ('88888888-8888-4888-8888-888888888888', 'KHL', 'Khulna',        22.845600, 89.540300)
on conflict (code) do update set
  name = excluded.name,
  latitude = excluded.latitude,
  longitude = excluded.longitude;

-- ---------------------------------------------------------------------------
-- 2. trips.demo_key + partial unique index (one row per service|date).
-- ---------------------------------------------------------------------------
alter table public.trips
  add column if not exists demo_key text;

create unique index if not exists trips_demo_key_unique
  on public.trips (demo_key)
  where demo_key is not null;

-- ---------------------------------------------------------------------------
-- 3. trip_seats.demo_reserved (default false; legacy rows read as free).
-- ---------------------------------------------------------------------------
alter table public.trip_seats
  add column if not exists demo_reserved boolean not null default false;

-- ---------------------------------------------------------------------------
-- 4. Owner/admin horizon refresh: today..+20d, 8 service templates,
--    40 seats (A1-A10/B1-B10/C1-C10/D1-D10) each, deterministic holds.
--
--    demo_key      = '<SERVICE>|<YYYY-MM-DD>' (e.g. 'RM701|2026-09-28').
--    hold hash key = '<SERVICE>|<YYYY-MM-DD>|<SEAT>' via md5, first two
--    bytes -> uniform roll in [0,100). Same date re-refresh is stable;
--    different dates give different patterns. No randomness, no clock
--    inside the roll (thresholds use the travel-date offset instead).
--
--    Occupancy thresholds (points, capped at 78):
--      base by departure wall-clock: morning 05:00-11:59 -> 42,
--        afternoon 12:00-18:59 -> 48, evening/overnight 19:00-04:59 -> 58;
--      Fri/Sat (isodow 5/6) +12; Thu (isodow 4) departures >= 18:00 +8;
--      travel_date = today (within ~24h) +12, +1/+2d (within ~72h) +6.
--    Seat is demo-held when roll < threshold.
--
--    SAFETY: trip rows are inserted ON CONFLICT DO NOTHING (existing rows
--    are never rewritten, protecting live bookings); seat rows are inserted
--    ON CONFLICT DO NOTHING and demo_reserved is only ever (re)set on rows
--    WHERE booking_id IS NULL. booking_id is never written here.
-- ---------------------------------------------------------------------------
create or replace function public.refresh_demo_horizon(p_days integer default 20)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_svc record;
  v_offset integer;
  v_date date;
  v_demo_key text;
  v_origin uuid;
  v_dest uuid;
  v_dep timestamptz;
  v_arr timestamptz;
  v_trip_id uuid;
  v_trips integer := 0;
  v_dow integer;
  v_base integer;
  v_thresh integer;
  v_c integer;
  v_n integer;
  v_seat text;
  v_digest bytea;
  v_roll double precision;
  v_reserved boolean;
begin
  if p_days is null or p_days < 0 or p_days > 60 then
    raise exception 'INVALID_HORIZON';
  end if;
  for v_svc in
    select * from (values
      ('RM701', 'Subarna Express (Demo)',   'DAC', 'CGP', time '07:00', 625, interval '5 hours 30 minutes'),
      ('RM702', 'Subarna Express (Demo)',   'CGP', 'DAC', time '15:30', 625, interval '5 hours 30 minutes'),
      ('RM741', 'Turna Night (Demo)',       'DAC', 'CGP', time '23:10', 625, interval '5 hours 30 minutes'),
      ('RM709', 'Parabat Express (Demo)',   'DAC', 'SYL', time '06:40', 540, interval '5 hours 20 minutes'),
      ('RM710', 'Upaban Express (Demo)',    'SYL', 'DAC', time '15:10', 540, interval '5 hours 20 minutes'),
      ('RM753', 'Silkcity Express (Demo)',  'DAC', 'RJH', time '14:40', 515, interval '4 hours 50 minutes'),
      ('RM725', 'Sundarban Express (Demo)', 'DAC', 'KHL', time '08:15', 700, interval '7 hours 30 minutes'),
      ('RM726', 'Sundarban Express (Demo)', 'KHL', 'DAC', time '19:10', 700, interval '7 hours 30 minutes')
    ) as t(code, train_name, origin_code, dest_code, dep_time, fare_bdt, duration)
  loop
    select id into v_origin from public.stations where code = v_svc.origin_code;
    select id into v_dest from public.stations where code = v_svc.dest_code;
    if v_origin is null or v_dest is null then
      raise exception 'DEMO_STATION_MISSING (%)', v_svc.code;
    end if;
    for v_offset in 0..p_days loop
      v_date := v_today + v_offset;
      v_demo_key := v_svc.code || '|' || to_char(v_date, 'YYYY-MM-DD');
      -- Wall-clock departure in Asia/Dhaka (+06, no DST) -> timestamptz.
      v_dep := ((v_date::text || ' ' || v_svc.dep_time::text)::timestamp at time zone 'Asia/Dhaka');
      v_arr := v_dep + v_svc.duration;
      insert into public.trips
        (train_name, origin_station_id, destination_station_id,
         departure_at, arrival_at, fare_bdt, active, demo_key)
      values
        (v_svc.train_name, v_origin, v_dest,
         v_dep, v_arr, v_svc.fare_bdt, true, v_demo_key)
      on conflict (demo_key) where demo_key is not null do nothing;
      select id into v_trip_id from public.trips where demo_key = v_demo_key;
      if not found then
        raise exception 'DEMO_TRIP_MISSING (%)', v_demo_key;
      end if;
      v_trips := v_trips + 1;
      -- Threshold for this service|date (points, cap 78).
      v_dow := extract(isodow from v_date)::integer; -- Mon=1..Sun=7
      v_base := case
        when v_svc.dep_time < time '12:00' then 42
        when v_svc.dep_time < time '19:00' then 48
        else 58
      end;
      v_thresh := v_base;
      if v_dow in (5, 6) then v_thresh := v_thresh + 12; end if;
      if v_dow = 4 and v_svc.dep_time >= time '18:00' then v_thresh := v_thresh + 8; end if;
      if v_offset = 0 then v_thresh := v_thresh + 12;
      elsif v_offset <= 2 then v_thresh := v_thresh + 6;
      end if;
      v_thresh := least(v_thresh, 78);
      for v_c in 1..4 loop
        for v_n in 1..10 loop
          v_seat := chr(ascii('A') + v_c - 1) || v_n::text;
          v_digest := decode(
            md5(v_svc.code || '|' || to_char(v_date, 'YYYY-MM-DD') || '|' || v_seat),
            'hex');
          v_roll := (get_byte(v_digest, 0) * 256 + get_byte(v_digest, 1))::double precision
            / 65535.0 * 100.0;
          v_reserved := v_roll < v_thresh::double precision;
          insert into public.trip_seats (trip_id, seat_code, demo_reserved)
          values (v_trip_id, v_seat, v_reserved)
          on conflict (trip_id, seat_code) do nothing;
          -- Deterministic hold re-assert: demo_reserved ONLY, and ONLY on
          -- rows with no real booking. booking_id is never written here.
          update public.trip_seats set demo_reserved = v_reserved
          where trip_id = v_trip_id and seat_code = v_seat and booking_id is null;
        end loop;
      end loop;
    end loop;
  end loop;
  return v_trips;
end;
$$;

comment on function public.refresh_demo_horizon(integer) is
  'F05: dynamic demo horizon (today..+p_days, default 20). DEMONSTRATION ONLY data. '
  'Deterministic demo_reserved holds from md5(service|date|seat); never writes booking_id. '
  'Owner/admin only: no grant to anon/authenticated. Past trips are kept (protects bookings).';

-- Owner/admin only: strip any public/client execute path (no grant added).
revoke all on function public.refresh_demo_horizon(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Booking RPC correction (F05): demo-held seats are unavailable.
--    CREATE OR REPLACE of public.book_trip_service, identical to
--    20260927063000_booking_atomic.sql except the two F05-marked lines:
--    the FOR UPDATE gate selects demo_reserved and raises SEAT_UNAVAILABLE
--    when booking_id IS NOT NULL OR demo_reserved IS TRUE, and the final
--    conditional mark additionally requires demo_reserved IS DISTINCT FROM
--    true. cancel_booking_service is untouched (it only releases rows
--    referencing its own booking_id; demo holds carry booking_id NULL).
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
    -- F05: also fetch demo_reserved so demo-held inventory blocks booking.
    select id, seat_code, booking_id, demo_reserved from public.trip_seats
      where trip_id=p_trip_id and seat_code=any(p_seat_codes)
      order by seat_code for update
  loop
    v_count := v_count+1;
    -- F05: unavailable when booked OR demo-held.
    if v_row.booking_id is not null or v_row.demo_reserved is true then raise exception 'SEAT_UNAVAILABLE'; end if;
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
  -- Conditional mark: succeeds only on still-unbooked, non-demo-held rows;
  -- row_count mismatch raises and rolls back everything (defense in depth
  -- behind FOR UPDATE).
  update public.trip_seats set booking_id=v_booking_id
    -- F05: never take a demo-held seat even under race.
    where trip_id=p_trip_id and seat_code=any(p_seat_codes) and booking_id is null and demo_reserved is distinct from true;
  get diagnostics v_count = row_count;
  if v_count <> v_n then raise exception 'CONCURRENT_CONFLICT'; end if;
  return v_booking_id;
end; $$;

comment on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) is
  'A05: atomic 1-4 seat booking. Service-role only; Edge passes JWT-verified user id. '
  'One transaction: FOR UPDATE seat locks in sorted order, idempotent on (user_id, request_id). '
  'Any seat conflict raises and rolls back all writes. '
  'F05: demo-held seats (demo_reserved) are unavailable like booked seats.';

-- Re-assert least privilege after the replace (CREATE OR REPLACE preserves
-- grants, but state it explicitly): service_role ONLY.
revoke all on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) from public,anon,authenticated;
grant execute on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) to service_role;

-- Coordinator proof checklist (live, after push):
--   a. select public.refresh_demo_horizon(); -> returns 168 (8 x 21 days);
--      re-run returns 168 with zero trip churn (only stable demo_reserved
--      re-asserts on unbooked seats).
--   b. 8 stations present; the 4 seeded station ids unchanged.
--   c. Per demo trip: 40 seats A1-D10; held share near tier target.
--   d. Booking a demo-held seat raises SEAT_UNAVAILABLE with zero writes.
--   e. Real booking then re-running refresh keeps booking_id.
--   f. No anon/authenticated execute on refresh_demo_horizon.
