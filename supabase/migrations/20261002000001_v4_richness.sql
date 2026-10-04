-- P12 — V4 richness: 24 stations + 32-service rolling horizon (coordinator).
-- Applies AFTER 20260928000001_demo_horizon.sql. All statements are
-- IF NOT EXISTS / ON CONFLICT / CREATE OR REPLACE guarded; re-runnable.
-- DEMONSTRATION ONLY — synthetic timetable/fares/occupancy, NOT real
-- railway data. Every generated train_name carries "(Demo)"; all ticket
-- artifacts must keep stating DEMONSTRATION ONLY.
--
-- What this file does:
--   1. Upserts 24 demo stations by code (8 stable ids/coords unchanged;
--      adds JOY/TNG/MYM/JAM/AKH/BRA/CXB/SRM/ISD/JSR/BOG/RGP/SDP/PBT/DIN/NOA).
--      New-station coordinates are SYNTHETIC placeholders (pack source files
--      carry VERIFY_BEFORE_APPLY for every station); the app must not use
--      them for map/navigation purposes.
--   2. Replaces refresh_demo_horizon() with the 32-service version: per-
--      service base occupancy, operating-weekday gating, cap 82. Safety
--      invariants unchanged: trips ON CONFLICT DO NOTHING; demo_reserved is
--      only (re)set WHERE booking_id IS NULL; booking_id never written;
--      owner/admin only (no grant to anon/authenticated).
--
-- Deviations from pack service_templates_v4.json (documented, deliberate):
--   a. Pack codes RM741/RM742 (Nilsagar DAC<->SDP) collide with the APPLIED
--      RM741 demo_key namespace (Turna Night DAC->CGP 23:10 rows already
--      generated for today..+20d). Reusing the code would attach new dates
--      to old-route rows via ON CONFLICT DO NOTHING. Nilsagar therefore
--      runs as RM743/RM744 (fresh demo_key namespace).
--   b. Applied RM741 (Turna Night DAC->CGP 23:10) and RM753 (Silkcity
--      DAC->RJH 14:40) are RETIRED from the generator: pack Turna services
--      RM705/RM706 and pack Silkcity RM721 cover those slots. Already-
--      generated RM741/RM753 trip + seat + booking rows are NEVER deleted
--      or rewritten (existing bookings stay valid); they simply age out of
--      the horizon while refreshes extend the replacement codes.
--   c. Overlapping codes RM701/702/709/710/725/726 keep their demo_key
--      namespaces and adopt the pack template values for NEW dates only
--      (existing rows untouched). RM710 new dates are named
--      'Parabat Express (Demo)' (pack) vs 'Upaban Express (Demo)' (old).

-- ---------------------------------------------------------------------------
-- 1. Stations: 24 demo stations, upsert by code, applied ids stable.
--    (id is never in the SET clause, so existing rows keep their ids.)
-- ---------------------------------------------------------------------------
insert into public.stations (id, code, name, latitude, longitude)
values
  ('11111111-1111-4111-8111-111111111111', 'DAC', 'Dhaka',         23.810300, 90.412500),
  ('55555555-5555-4555-8555-555555555555', 'AIR', 'Dhaka Airport', 23.843100, 90.397300),
  ('10101010-1010-4101-8101-101010101010', 'JOY', 'Joydebpur',     23.993400, 90.384700),
  ('12121212-1212-4121-8121-121212121212', 'TNG', 'Tangail',       24.251200, 89.917000),
  ('13131313-1313-4131-8131-131313131313', 'MYM', 'Mymensingh',    24.747100, 90.420300),
  ('14141414-1414-4141-8141-141414141414', 'JAM', 'Jamalpur',      24.937500, 89.937200),
  ('15151515-1515-4151-8151-151515151515', 'AKH', 'Akhaura',       23.862400, 91.206500),
  ('16161616-1616-4161-8161-161616161616', 'BRA', 'Brahmanbaria',  23.960800, 91.111500),
  ('66666666-6666-4666-8666-666666666666', 'CML', 'Cumilla',       23.460700, 91.180900),
  ('77777777-7777-4777-8777-777777777777', 'FEN', 'Feni',          23.023500, 91.384100),
  ('22222222-2222-4222-8222-222222222222', 'CGP', 'Chattogram',    22.356900, 91.783200),
  ('17171717-1717-4171-8171-171717171717', 'CXB', 'Cox''s Bazar',  21.427200, 92.005800),
  ('33333333-3333-4333-8333-333333333333', 'SYL', 'Sylhet',        24.894900, 91.869200),
  ('18181818-1818-4181-8181-181818181818', 'SRM', 'Sreemangal',    24.308400, 91.733300),
  ('44444444-4444-4444-8444-444444444444', 'RJH', 'Rajshahi',      24.374500, 88.604200),
  ('19191919-1919-4191-8191-191919191919', 'ISD', 'Ishwardi',      24.128500, 89.066700),
  ('88888888-8888-4888-8888-888888888888', 'KHL', 'Khulna',        22.845600, 89.540300),
  ('20202020-2020-4202-8202-202020202020', 'JSR', 'Jashore',       23.165700, 89.208100),
  ('21212121-2121-4212-8212-212121212121', 'BOG', 'Bogura',        24.846500, 89.373300),
  ('23232323-2323-4232-8232-232323232323', 'RGP', 'Rangpur',       25.743100, 89.275200),
  ('24242424-2424-4242-8242-242424242424', 'SDP', 'Saidpur',       25.778200, 88.891700),
  ('25252525-2525-4252-8252-252525252525', 'PBT', 'Parbatipur',    25.655900, 88.913600),
  ('26262626-2626-4262-8262-262626262626', 'DIN', 'Dinajpur',      25.627900, 88.644300),
  ('27272727-2727-4272-8272-272727272727', 'NOA', 'Noakhali',      22.869300, 91.099000)
on conflict (code) do update set
  name = excluded.name,
  latitude = excluded.latitude,
  longitude = excluded.longitude;

-- ---------------------------------------------------------------------------
-- 2. Owner/admin horizon refresh: today..+20d, 32 service templates,
--    40 seats (A1-A10/B1-B10/C1-C10/D1-D10) each, deterministic holds.
--
--    demo_key      = '<SERVICE>|<YYYY-MM-DD>' (e.g. 'RM701|2026-10-02').
--    Non-operating weekdays are skipped (6-day services rest Sundays),
--    preserving honest no-result demo states.
--    hold hash key = '<SERVICE>|<YYYY-MM-DD>|<SEAT>' via md5, first two
--    bytes -> uniform roll in [0,100). Same date re-refresh is stable;
--    different dates give different patterns. No randomness, no clock
--    inside the roll (thresholds use the travel-date offset instead).
--
--    Occupancy thresholds (points, capped at 82):
--      per-service base_occupancy_pct (pack, synthetic bands);
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
      ('RM701', 'Subarna Express (Demo)',   'DAC', 'CGP', time '07:00', 330, 625, 44, array[1,2,3,4,5,6,7]),
      ('RM702', 'Subarna Express (Demo)',   'CGP', 'DAC', time '15:30', 330, 625, 49, array[1,2,3,4,5,6,7]),
      ('RM703', 'Sonar Bangla (Demo)',      'DAC', 'CGP', time '16:45', 315, 690, 58, array[1,2,3,4,5,6]),
      ('RM704', 'Sonar Bangla (Demo)',      'CGP', 'DAC', time '07:15', 315, 690, 51, array[1,2,3,4,5,6]),
      ('RM705', 'Turna Night (Demo)',       'DAC', 'CGP', time '23:05', 390, 625, 63, array[1,2,3,4,5,6,7]),
      ('RM706', 'Turna Night (Demo)',       'CGP', 'DAC', time '23:20', 390, 625, 63, array[1,2,3,4,5,6,7]),
      ('RM709', 'Parabat Express (Demo)',   'DAC', 'SYL', time '06:40', 390, 540, 47, array[1,2,3,4,5,6,7]),
      ('RM710', 'Parabat Express (Demo)',   'SYL', 'DAC', time '15:10', 390, 540, 52, array[1,2,3,4,5,6,7]),
      ('RM711', 'Upaban Express (Demo)',    'DAC', 'SYL', time '21:50', 430, 510, 59, array[1,2,3,4,5,6,7]),
      ('RM712', 'Upaban Express (Demo)',    'SYL', 'DAC', time '22:00', 430, 510, 59, array[1,2,3,4,5,6,7]),
      ('RM713', 'Jayantika Express (Demo)', 'DAC', 'SYL', time '11:15', 420, 520, 46, array[1,2,3,4,5,6]),
      ('RM714', 'Jayantika Express (Demo)', 'SYL', 'DAC', time '10:30', 420, 520, 46, array[1,2,3,4,5,6]),
      ('RM721', 'Silkcity Express (Demo)',  'DAC', 'RJH', time '14:40', 350, 515, 49, array[1,2,3,4,5,6]),
      ('RM722', 'Silkcity Express (Demo)',  'RJH', 'DAC', time '07:30', 350, 515, 50, array[1,2,3,4,5,6]),
      ('RM723', 'Padma Express (Demo)',     'DAC', 'RJH', time '23:00', 365, 500, 61, array[1,2,3,4,5,6,7]),
      ('RM724', 'Padma Express (Demo)',     'RJH', 'DAC', time '16:00', 365, 500, 55, array[1,2,3,4,5,6,7]),
      ('RM725', 'Sundarban Express (Demo)', 'DAC', 'KHL', time '08:15', 510, 700, 50, array[1,2,3,4,5,6,7]),
      ('RM726', 'Sundarban Express (Demo)', 'KHL', 'DAC', time '19:10', 510, 700, 56, array[1,2,3,4,5,6,7]),
      ('RM727', 'Chitra Express (Demo)',    'DAC', 'KHL', time '19:00', 500, 680, 57, array[1,2,3,4,5,6,7]),
      ('RM728', 'Chitra Express (Demo)',    'KHL', 'DAC', time '09:00', 500, 680, 50, array[1,2,3,4,5,6,7]),
      ('RM731', 'Ekota Express (Demo)',     'DAC', 'DIN', time '10:15', 620, 780, 48, array[1,2,3,4,5,6,7]),
      ('RM732', 'Ekota Express (Demo)',     'DIN', 'DAC', time '21:10', 620, 780, 60, array[1,2,3,4,5,6,7]),
      ('RM733', 'Drutajan Express (Demo)',  'DAC', 'DIN', time '20:00', 600, 760, 61, array[1,2,3,4,5,6,7]),
      ('RM734', 'Drutajan Express (Demo)',  'DIN', 'DAC', time '08:00', 600, 760, 51, array[1,2,3,4,5,6,7]),
      ('RM743', 'Nilsagar Express (Demo)',  'DAC', 'SDP', time '06:45', 560, 720, 48, array[1,2,3,4,5,6,7]),
      ('RM744', 'Nilsagar Express (Demo)',  'SDP', 'DAC', time '20:00', 560, 720, 58, array[1,2,3,4,5,6,7]),
      ('RM751', 'Coastal Express (Demo)',   'CGP', 'CXB', time '07:30', 210, 390, 54, array[1,2,3,4,5,6,7]),
      ('RM752', 'Coastal Express (Demo)',   'CXB', 'CGP', time '15:30', 210, 390, 54, array[1,2,3,4,5,6,7]),
      ('RM761', 'Haor Express (Demo)',      'DAC', 'MYM', time '07:20', 165, 260, 43, array[1,2,3,4,5,6,7]),
      ('RM762', 'Haor Express (Demo)',      'MYM', 'DAC', time '17:30', 165, 260, 49, array[1,2,3,4,5,6,7]),
      ('RM771', 'Meghna Express (Demo)',    'CGP', 'NOA', time '08:10', 230, 360, 45, array[1,2,3,4,5,6]),
      ('RM772', 'Meghna Express (Demo)',    'NOA', 'CGP', time '16:25', 230, 360, 49, array[1,2,3,4,5,6])
    ) as t(code, train_name, origin_code, dest_code, dep_time, dur_min, fare_bdt, base_occ, dow)
  loop
    select id into v_origin from public.stations where code = v_svc.origin_code;
    select id into v_dest from public.stations where code = v_svc.dest_code;
    if v_origin is null or v_dest is null then
      raise exception 'DEMO_STATION_MISSING (%)', v_svc.code;
    end if;
    for v_offset in 0..p_days loop
      v_date := v_today + v_offset;
      v_dow := extract(isodow from v_date)::integer; -- Mon=1..Sun=7
      -- Non-operating weekday: skip (honest no-result demo state).
      if not (v_dow = any (v_svc.dow)) then
        continue;
      end if;
      v_demo_key := v_svc.code || '|' || to_char(v_date, 'YYYY-MM-DD');
      -- Wall-clock departure in Asia/Dhaka (+06, no DST) -> timestamptz.
      v_dep := ((v_date::text || ' ' || v_svc.dep_time::text)::timestamp at time zone 'Asia/Dhaka');
      v_arr := v_dep + (v_svc.dur_min || ' minutes')::interval;
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
      -- Threshold for this service|date (points, cap 82).
      v_thresh := v_svc.base_occ;
      if v_dow in (5, 6) then v_thresh := v_thresh + 12; end if;
      if v_dow = 4 and v_svc.dep_time >= time '18:00' then v_thresh := v_thresh + 8; end if;
      if v_offset = 0 then v_thresh := v_thresh + 12;
      elsif v_offset <= 2 then v_thresh := v_thresh + 6;
      end if;
      v_thresh := least(v_thresh, 82);
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
  'P12: dynamic demo horizon (today..+p_days, default 20) over 32 service '
  'templates. DEMONSTRATION ONLY data. Deterministic demo_reserved holds '
  'from md5(service|date|seat) against per-service base occupancy (cap 82); '
  'never writes booking_id. Non-operating weekdays skipped. '
  'Owner/admin only: no grant to anon/authenticated. Past trips are kept '
  '(protects bookings). Retired codes RM741(Turna)/RM753 keep existing rows.';

-- Owner/admin only: strip any public/client execute path (no grant added).
revoke all on function public.refresh_demo_horizon(integer) from public, anon, authenticated;

-- Coordinator proof checklist (live, after push):
--   a. select count(*) from public.stations; -> 24.
--   b. 8 stable ids unchanged (compare with §1 uuids).
--   c. select public.refresh_demo_horizon(); -> ~648 (32 x 21 minus ~24
--      skipped Sunday rests); re-run returns same count with zero trip churn.
--   d. Per demo trip: 40 seats A1-D10; held share near tier target.
--   e. Core corridors return 2-4 options on an operating weekday, e.g.
--      DAC->CGP (RM701/703/705), DAC->SYL (RM709/711/713), DAC->RJH
--      (RM721/723), DAC->KHL (RM725/727).
--   f. Booking a demo-held seat raises SEAT_UNAVAILABLE with zero writes.
--   g. Real booking then re-running refresh keeps booking_id.
--   h. No anon/authenticated execute on refresh_demo_horizon.
