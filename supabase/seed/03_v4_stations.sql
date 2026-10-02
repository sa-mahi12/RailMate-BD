-- P11 prep draft — V4 station catalog expansion (NOT APPLIED).
-- DEMONSTRATION ONLY — all values are synthetic demo data. Nothing here
-- claims official Bangladesh Railway accuracy. Ticket artifacts must keep
-- stating DEMONSTRATION ONLY.
--
-- Source of truth: pack data/stations_v4.json (24 stations).
-- Deviation note: the pack file carries coordinates:"VERIFY_BEFORE_APPLY"
-- for every station, so numeric coordinates below are plausible SYNTHETIC
-- placeholders. The 8 live codes keep their exact applied coordinates;
-- the 16 new coordinates REQUIRE verification before any map use (P12).
--
-- SCOPE: staging table ONLY. This file creates NO production table, touches
-- NO RLS/policy, and writes NO credentials. The coordinator adapts the
-- commented production template (§3) into the P12 migration.
-- Idempotent: CREATE TABLE IF NOT EXISTS + INSERT ... ON CONFLICT.
--
-- Stable station UUIDs (existing rows keep their applied ids):
--   DAC 11111111-...  CGP 22222222-...  SYL 33333333-...  RJH 44444444-...
--   (from 20260927000005_demo_seed.sql)
--   AIR 55555555-...  CML 66666666-...  FEN 77777777-...  KHL 88888888-...
--   (from 20260928000001_demo_horizon.sql §1)
-- New UUIDs below are fixed draft ids for P12 review (v4-format, unique).

-- ---------------------------------------------------------------------------
-- §1. Staging table (draft namespace only — never a production name).
-- ---------------------------------------------------------------------------
create table if not exists public._p11_stations_draft (
  code text primary key,
  name text not null,
  district text not null,
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  station_uuid uuid not null unique,
  coord_status text not null default 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE',
  constraint _p11_stations_code_fmt check (code ~ '^[A-Z]{3}$')
);

-- ---------------------------------------------------------------------------
-- §2. Draft rows: 24 stations (8 stable + 16 new). Re-runnable.
-- ---------------------------------------------------------------------------
insert into public._p11_stations_draft
  (code, name, district, latitude, longitude, station_uuid, coord_status)
values
  -- Stable 8 keep their applied ids + coords (marked STABLE_APPLIED);
  -- new 16 carry synthetic plausible coords (MUST be verified before map use).
  ('DAC', 'Dhaka',         'Dhaka',      23.810300, 90.412500,
    '11111111-1111-4111-8111-111111111111', 'STABLE_APPLIED'),
  ('AIR', 'Dhaka Airport', 'Dhaka',      23.843100, 90.397300,
    '55555555-5555-4555-8555-555555555555', 'STABLE_APPLIED'),
  ('JOY', 'Joydebpur',   'Gazipur',     23.993400, 90.384700,
    '10101010-1010-4101-8101-101010101010', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('TNG', 'Tangail',     'Tangail',     24.251200, 89.917000,
    '12121212-1212-4121-8121-121212121212', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('MYM', 'Mymensingh',  'Mymensingh',  24.747100, 90.420300,
    '13131313-1313-4131-8131-131313131313', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('JAM', 'Jamalpur',    'Jamalpur',    24.937500, 89.937200,
    '14141414-1414-4141-8141-141414141414', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('AKH', 'Akhaura',     'Brahmanbaria', 23.862400, 91.206500,
    '15151515-1515-4151-8151-151515151515', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('BRA', 'Brahmanbaria', 'Brahmanbaria', 23.960800, 91.111500,
    '16161616-1616-4161-8161-161616161616', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('CML', 'Cumilla',       'Cumilla',    23.460700, 91.180900,
    '66666666-6666-4666-8666-666666666666', 'STABLE_APPLIED'),
  ('FEN', 'Feni',          'Feni',       23.023500, 91.384100,
    '77777777-7777-4777-8777-777777777777', 'STABLE_APPLIED'),
  ('CGP', 'Chattogram',    'Chattogram', 22.356900, 91.783200,
    '22222222-2222-4222-8222-222222222222', 'STABLE_APPLIED'),
  ('CXB', 'Cox''s Bazar', 'Cox''s Bazar', 21.427200, 92.005800,
    '17171717-1717-4171-8171-171717171717', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('SYL', 'Sylhet',        'Sylhet',     24.894900, 91.869200,
    '33333333-3333-4333-8333-333333333333', 'STABLE_APPLIED'),
  ('SRM', 'Sreemangal',  'Moulvibazar', 24.308400, 91.733300,
    '18181818-1818-4181-8181-181818181818', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('RJH', 'Rajshahi',      'Rajshahi',   24.374500, 88.604200,
    '44444444-4444-4444-8444-444444444444', 'STABLE_APPLIED'),
  ('ISD', 'Ishwardi',    'Pabna',       24.128500, 89.066700,
    '19191919-1919-4191-8191-191919191919', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('KHL', 'Khulna',        'Khulna',     22.845600, 89.540300,
    '88888888-8888-4888-8888-888888888888', 'STABLE_APPLIED'),
  ('JSR', 'Jashore',     'Jashore',     23.165700, 89.208100,
    '20202020-2020-4202-8202-202020202020', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('BOG', 'Bogura',      'Bogura',      24.846500, 89.373300,
    '21212121-2121-4212-8212-212121212121', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('RGP', 'Rangpur',     'Rangpur',     25.743100, 89.275200,
    '23232323-2323-4232-8232-232323232323', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('SDP', 'Saidpur',     'Nilphamari',  25.778200, 88.891700,
    '24242424-2424-4242-8242-242424242424', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('PBT', 'Parbatipur',  'Dinajpur',    25.655900, 88.913600,
    '25252525-2525-4252-8252-252525252525', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('DIN', 'Dinajpur',    'Dinajpur',    25.627900, 88.644300,
    '26262626-2626-4262-8262-262626262626', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE'),
  ('NOA', 'Noakhali',    'Noakhali',    22.869300, 91.099000,
    '27272727-2727-4272-8272-272727272727', 'SYNTHETIC_PLACEHOLDER_VERIFY_BEFORE_MAP_USE')
on conflict (code) do update set
  name = excluded.name,
  district = excluded.district,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  station_uuid = excluded.station_uuid,
  coord_status = excluded.coord_status;

-- ---------------------------------------------------------------------------
-- §3. P12 production template (COMMENT ONLY — coordinator adapts this into
-- the P12 migration; this worker must not apply it).
-- Upsert by stable code; id column is never in the SET clause so applied
-- ids stay stable:
--
--   insert into public.stations (id, code, name, latitude, longitude)
--   select station_uuid, code, name, latitude, longitude
--     from public._p11_stations_draft
--   on conflict (code) do update set
--     name = excluded.name,
--     latitude = excluded.latitude,
--     longitude = excluded.longitude;
--
-- Verification queries for P12 (run live after migration):
--   select count(*) from public.stations where code in
--     (select code from public._p11_stations_draft);            -- expect 24
--   select id, code from public.stations where code in
--     ('DAC','CGP','SYL','RJH','AIR','CML','FEN','KHL') order by code;
--     -- ids must equal the STABLE_APPLIED uuids above.
-- ---------------------------------------------------------------------------
