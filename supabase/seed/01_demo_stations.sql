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
