-- Reviewed B01 demo seed applied as migration (idempotent INSERTs only).
-- Source files: supabase/seed/01_demo_stations.sql + 02_demo_trips_seats.sql.

-- B01 demo seed: stations (part 1 of 2).
-- DEMONSTRATION ONLY — synthetic data, NOT real timetable information.
-- NOT APPLIED. Coordinator reviews and applies to the hosted project
-- (ref psuzlyingfmstnyfvlnj) under the post-pass gate. Never apply twice
-- blindly: every statement below is idempotent (ON CONFLICT DO NOTHING).
--
-- Stable demo station IDs (fixed UUIDs, safe to reference from 02 file):
--   Dhaka      11111111-1111-4111-8111-111111111111  code DAC
--   Chattogram 22222222-2222-4222-8222-222222222222  code CGP
--   Sylhet     33333333-3333-4333-8333-333333333333  code SYL
--   Rajshahi   44444444-4444-4444-8444-444444444444  code RJH
--
-- NOTE (unresolved B01-U1): the applied schema
-- (supabase/migrations/20260927000001_initial_schema.sql) defines NO
-- is_demo/demo flag column on any table, so demo-marking is carried
-- in-band by the 'DEMO ' train_name prefix in 02_demo_trips_seats.sql
-- plus this header. Adding a real is_demo column requires a
-- coordinator-reviewed migration; this worker must not alter schema.

insert into public.stations (id, code, name, latitude, longitude)
values
  ('11111111-1111-4111-8111-111111111111', 'DAC', 'Dhaka', 23.810300, 90.412500),
  ('22222222-2222-4222-8222-222222222222', 'CGP', 'Chattogram', 22.356900, 91.783200),
  ('33333333-3333-4333-8333-333333333333', 'SYL', 'Sylhet', 24.894900, 91.869200),
  ('44444444-4444-4444-8444-444444444444', 'RJH', 'Rajshahi', 24.374500, 88.604200)
on conflict do nothing;

-- B01 demo seed: trips + one-coach seat layout (part 2 of 2).
-- DEMONSTRATION ONLY — synthetic data, NOT real timetable information.
-- NOT APPLIED. Coordinator reviews and applies after 01_demo_stations.sql.
-- Idempotent: trips use fixed UUIDs with ON CONFLICT DO NOTHING; seats use
-- the (trip_id, seat_code) unique target so re-runs add nothing.
--
-- Stable demo trip IDs:
--   T1  a1a1a1a1-1111-4111-8111-aaaaaaaaaaaa  DAC -> CGP  2026-10-15
--   T2  b2b2b2b2-2222-4222-8222-bbbbbbbbbbbb  DAC -> SYL  2026-10-15
--   T3  c3c3c3c3-3333-4333-8333-cccccccccccc  DAC -> RJH  2026-10-16
--   T4  d4d4d4d4-4444-4444-8444-dddddddddddd  CGP -> DAC  2026-10-16
--
-- Route/date search is served by trips(origin_station_id,
-- destination_station_id, departure_at) via the trips_search_idx index.
-- All train_name values carry the 'DEMO ' prefix (see B01-U1 note in 01 file:
-- applied schema has no is_demo column). Seat rows are free inventory
-- (booking_id NULL); bookings must only be created by the atomic
-- server-side booking operation, never by seed.

insert into public.trips (
  id, train_name, origin_station_id, destination_station_id,
  departure_at, arrival_at, fare_bdt, active
)
values
  ('a1a1a1a1-1111-4111-8111-aaaaaaaaaaaa', 'DEMO Trial Runner 101',
   '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '2026-10-15 07:00:00+06', '2026-10-15 12:30:00+06', 450, true),
  ('b2b2b2b2-2222-4222-8222-bbbbbbbbbbbb', 'DEMO Trial Runner 202',
   '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333',
   '2026-10-15 08:30:00+06', '2026-10-15 14:00:00+06', 380, true),
  ('c3c3c3c3-3333-4333-8333-cccccccccccc', 'DEMO Trial Runner 303',
   '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444',
   '2026-10-16 09:00:00+06', '2026-10-16 13:30:00+06', 350, true),
  ('d4d4d4d4-4444-4444-8444-dddddddddddd', 'DEMO Trial Runner 404',
   '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111',
   '2026-10-16 15:00:00+06', '2026-10-16 20:30:00+06', 450, true)
on conflict do nothing;

-- One-coach schematic: seats A-01 .. A-10 per demo trip, unbooked.
insert into public.trip_seats (trip_id, seat_code)
select 'a1a1a1a1-1111-4111-8111-aaaaaaaaaaaa', 'A-' || lpad(g::text, 2, '0')
from generate_series(1, 10) as g
on conflict (trip_id, seat_code) do nothing;

insert into public.trip_seats (trip_id, seat_code)
select 'b2b2b2b2-2222-4222-8222-bbbbbbbbbbbb', 'A-' || lpad(g::text, 2, '0')
from generate_series(1, 10) as g
on conflict (trip_id, seat_code) do nothing;

insert into public.trip_seats (trip_id, seat_code)
select 'c3c3c3c3-3333-4333-8333-cccccccccccc', 'A-' || lpad(g::text, 2, '0')
from generate_series(1, 10) as g
on conflict (trip_id, seat_code) do nothing;

insert into public.trip_seats (trip_id, seat_code)
select 'd4d4d4d4-4444-4444-8444-dddddddddddd', 'A-' || lpad(g::text, 2, '0')
from generate_series(1, 10) as g
on conflict (trip_id, seat_code) do nothing;

