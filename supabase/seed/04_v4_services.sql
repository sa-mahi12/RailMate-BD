-- P11 prep draft — V4 synthetic service templates (NOT APPLIED).
-- DEMONSTRATION ONLY — all names/times/fares/durations are synthetic demo
-- data. Nothing here claims official Bangladesh Railway accuracy. Ticket
-- artifacts must keep stating DEMONSTRATION ONLY.
--
-- Source of truth: pack data/service_templates_v4.json (32 templates).
-- Deviations: none on service fields — codes, names, station pairs, times,
-- durations, fares, baselines and operating weekdays are transcribed exactly.
-- Fare/duration plausibility spot-check (synthetic bands, longer = costlier):
--   short  (165-230 min) -> 260-390 BDT  (MYM/CXB/NOA legs)
--   medium (315-430 min) -> 500-690 BDT  (CGP/SYL/RJH legs)
--   long   (500-620 min) -> 680-780 BDT  (KHL/DIN/SDP legs)
--   fare-per-minute across all 32 templates sits in ~1.2-2.2 BDT/min.
--
-- SCOPE: staging table ONLY. This file creates NO production table, touches
-- NO RLS/policy, writes NO trips/seats/bookings and contains NO credentials.
-- Idempotent: CREATE TABLE IF NOT EXISTS + INSERT ... ON CONFLICT.
-- The coordinator adapts §3 into the P12 migration (service list for the
-- rolling-horizon generator) and §4 documents the deterministic occupancy
-- formula P12 must implement.

-- ---------------------------------------------------------------------------
-- §1. Staging table (draft namespace only — never a production name).
-- ---------------------------------------------------------------------------
create table if not exists public._p11_services_draft (
  service_code text primary key,
  train_name text not null,
  origin_code text not null references public._p11_stations_draft(code),
  dest_code text not null references public._p11_stations_draft(code),
  departure_local time not null,
  duration_minutes integer not null check (duration_minutes > 0),
  fare_bdt integer not null check (fare_bdt >= 0),
  base_occupancy_pct integer not null check (base_occupancy_pct between 0 and 100),
  operating_isodow integer[] not null,
  schedule_status text not null default 'SYNTHETIC_DEMO',
  constraint _p11_services_endpoints check (origin_code <> dest_code)
);

-- ---------------------------------------------------------------------------
-- §2. Draft rows: 32 synthetic service templates. Re-runnable.
-- Apply order: 03_v4_stations.sql first (FK target).
-- ---------------------------------------------------------------------------
insert into public._p11_services_draft
  (service_code, train_name, origin_code, dest_code, departure_local,
   duration_minutes, fare_bdt, base_occupancy_pct, operating_isodow,
   schedule_status)
values
  ('RM701', 'Subarna Express (Demo)', 'DAC', 'CGP', time '07:00', 330, 625, 44, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM702', 'Subarna Express (Demo)', 'CGP', 'DAC', time '15:30', 330, 625, 49, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM703', 'Sonar Bangla (Demo)',    'DAC', 'CGP', time '16:45', 315, 690, 58, array[1,2,3,4,5,6],   'SYNTHETIC_DEMO'),
  ('RM704', 'Sonar Bangla (Demo)',    'CGP', 'DAC', time '07:15', 315, 690, 51, array[1,2,3,4,5,6],   'SYNTHETIC_DEMO'),
  ('RM705', 'Turna Night (Demo)',     'DAC', 'CGP', time '23:05', 390, 625, 63, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM706', 'Turna Night (Demo)',     'CGP', 'DAC', time '23:20', 390, 625, 63, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM709', 'Parabat Express (Demo)', 'DAC', 'SYL', time '06:40', 390, 540, 47, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM710', 'Parabat Express (Demo)', 'SYL', 'DAC', time '15:10', 390, 540, 52, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM711', 'Upaban Express (Demo)',  'DAC', 'SYL', time '21:50', 430, 510, 59, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM712', 'Upaban Express (Demo)',  'SYL', 'DAC', time '22:00', 430, 510, 59, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM713', 'Jayantika Express (Demo)', 'DAC', 'SYL', time '11:15', 420, 520, 46, array[1,2,3,4,5,6], 'SYNTHETIC_DEMO'),
  ('RM714', 'Jayantika Express (Demo)', 'SYL', 'DAC', time '10:30', 420, 520, 46, array[1,2,3,4,5,6], 'SYNTHETIC_DEMO'),
  ('RM721', 'Silkcity Express (Demo)', 'DAC', 'RJH', time '14:40', 350, 515, 49, array[1,2,3,4,5,6],   'SYNTHETIC_DEMO'),
  ('RM722', 'Silkcity Express (Demo)', 'RJH', 'DAC', time '07:30', 350, 515, 50, array[1,2,3,4,5,6],   'SYNTHETIC_DEMO'),
  ('RM723', 'Padma Express (Demo)',   'DAC', 'RJH', time '23:00', 365, 500, 61, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM724', 'Padma Express (Demo)',   'RJH', 'DAC', time '16:00', 365, 500, 55, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM725', 'Sundarban Express (Demo)', 'DAC', 'KHL', time '08:15', 510, 700, 50, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM726', 'Sundarban Express (Demo)', 'KHL', 'DAC', time '19:10', 510, 700, 56, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM727', 'Chitra Express (Demo)',  'DAC', 'KHL', time '19:00', 500, 680, 57, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM728', 'Chitra Express (Demo)',  'KHL', 'DAC', time '09:00', 500, 680, 50, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM731', 'Ekota Express (Demo)',   'DAC', 'DIN', time '10:15', 620, 780, 48, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM732', 'Ekota Express (Demo)',   'DIN', 'DAC', time '21:10', 620, 780, 60, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM733', 'Drutajan Express (Demo)', 'DAC', 'DIN', time '20:00', 600, 760, 61, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM734', 'Drutajan Express (Demo)', 'DIN', 'DAC', time '08:00', 600, 760, 51, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM741', 'Nilsagar Express (Demo)', 'DAC', 'SDP', time '06:45', 560, 720, 48, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM742', 'Nilsagar Express (Demo)', 'SDP', 'DAC', time '20:00', 560, 720, 58, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM751', 'Coastal Express (Demo)', 'CGP', 'CXB', time '07:30', 210, 390, 54, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM752', 'Coastal Express (Demo)', 'CXB', 'CGP', time '15:30', 210, 390, 54, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM761', 'Haor Express (Demo)',    'DAC', 'MYM', time '07:20', 165, 260, 43, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM762', 'Haor Express (Demo)',    'MYM', 'DAC', time '17:30', 165, 260, 49, array[1,2,3,4,5,6,7], 'SYNTHETIC_DEMO'),
  ('RM771', 'Meghna Express (Demo)',  'CGP', 'NOA', time '08:10', 230, 360, 45, array[1,2,3,4,5,6],   'SYNTHETIC_DEMO'),
  ('RM772', 'Meghna Express (Demo)',  'NOA', 'CGP', time '16:25', 230, 360, 49, array[1,2,3,4,5,6],   'SYNTHETIC_DEMO')
on conflict (service_code) do update set
  train_name = excluded.train_name,
  origin_code = excluded.origin_code,
  dest_code = excluded.dest_code,
  departure_local = excluded.departure_local,
  duration_minutes = excluded.duration_minutes,
  fare_bdt = excluded.fare_bdt,
  base_occupancy_pct = excluded.base_occupancy_pct,
  operating_isodow = excluded.operating_isodow,
  schedule_status = excluded.schedule_status;

-- ---------------------------------------------------------------------------
-- §3. P12 integration notes (COMMENT ONLY — coordinator-owned migration).
--   a. Extend refresh_demo_horizon()'s service VALUES list from 8 to these
--      32 templates (read from this staging table or inline the list).
--   b. Gate each service|date on operating_isodow: skip the date when
--      extract(isodow from travel_date) is not in the service's array.
--      6-day services (RM703/704/713/714/721/722/771/772) therefore rest
--      ~3 days per 21-day window — this preserves honest no-result /
--      non-operating-day demo states (scenario matrix §"No-result").
--   c. RECONCILE: applied 20260928000001_demo_horizon.sql hardcodes code
--      'RM753' for Silkcity DAC->RJH 14:40. Pack source uses 'RM721' for
--      that slot. Prefer pack 'RM721'; leave already-generated RM753
--      demo_keys untouched (never delete trips that may carry bookings).
--   d. Horizon volume: 32 services x 21 days = 672 keys minus ~24 skipped
--      non-operating days ≈ 648 trips; 40 seats each ≈ 25,920 seat rows.
--      Fits the richness plan (500-650 trips, 20k-26k seats).
--   e. Intermediate stations with no originating service (JOY/TNG/JAM/AKH/
--      BRA/SRM/ISD/JSR/BOG/RGP/PBT) intentionally keep unsupported pairs
--      returning empty — required by the scenario matrix. Do NOT invent
--      services for them in P12 without a coordinator decision.
--
-- Verification queries for P12 (live, after migration + refresh):
--   select count(*) from public._p11_services_draft;          -- expect 32
--   select origin_code, dest_code, count(*)
--     from public._p11_services_draft group by 1, 2 order by 1, 2;
--   select public.refresh_demo_horizon();                       -- expect ~648
--   -- core corridors return 2-4 options on an operating weekday, e.g.
--   -- DAC->CGP (3: RM701/703/705), DAC->SYL (3), DAC->RJH (2), DAC->KHL (2).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- §4. Rolling-horizon generation approach for P12 (deterministic occupancy).
-- Same md5-seed family as applied 20260928000001_demo_horizon.sql §4, with
-- the per-service baseline taken from base_occupancy_pct instead of the
-- wall-clock tier:
--
--   demo_key  = service_code || '|' || to_char(travel_date,'YYYY-MM-DD')
--   seat_code = 'A1'..'D10' (40 seats: coaches A-D x 1-10)
--   digest    = md5(service_code || '|' || YYYY-MM-DD || '|' || seat_code)
--   roll      = (byte0 * 256 + byte1) / 65535.0 * 100.0   -- uniform [0,100)
--   threshold = least(base_occupancy_pct + dow_add + prox_add, 82)
--     dow_add : +12 when isodow in (5,6) [Fri/Sat];
--               +8 when isodow = 4 and departure_local >= 18:00 [Thu eve]
--     prox_add: +12 when travel_date = today (offset 0);
--               +6  when offset in (1,2)
--   held      = roll < threshold  →  demo_reserved = true
--
-- Invariants P12 must preserve:
--   - same service|date|seat re-refresh is stable (no clock/random in roll);
--   - demo_reserved is (re)set ONLY on rows WHERE booking_id IS NULL;
--   - booking_id is NEVER written by the generator;
--   - trip inserts use ON CONFLICT (demo_key) DO NOTHING (never rewrite);
--   - unavailable = booking_id IS NOT NULL OR demo_reserved IS TRUE;
--   - cap 82 keeps bookable seats on most trips while the seed spread still
--     yields high/medium/low/near-full occupancy examples across dates.
-- ---------------------------------------------------------------------------
