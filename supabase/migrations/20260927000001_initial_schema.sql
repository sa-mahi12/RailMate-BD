-- DRAFT / NOT APPLIED. Review in a disposable *hosted* Supabase staging project first.
-- Do not apply to an existing populated project without inventory, DB+Storage backup and approval.
-- Note: schema is the intended minimum; refine migrations and RLS together before deployment.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.usernames (
  username text primary key check (username ~ '^[a-z0-9_]{3,20}$'),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.stations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  latitude numeric(9,6), longitude numeric(9,6)
);
create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  train_name text not null,
  origin_station_id uuid not null references public.stations(id),
  destination_station_id uuid not null references public.stations(id),
  departure_at timestamptz not null,
  arrival_at timestamptz not null,
  fare_bdt integer not null check (fare_bdt >= 0),
  active boolean not null default true,
  constraint distinct_endpoints check (origin_station_id <> destination_station_id),
  constraint valid_schedule check (arrival_at > departure_at)
);
create index if not exists trips_search_idx
  on public.trips(origin_station_id,destination_station_id,departure_at);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  trip_id uuid not null references public.trips(id),
  request_id uuid not null,
  request_fingerprint text not null,
  status text not null check (status in ('CONFIRMED','CANCELLED')),
  total_fare_bdt integer not null check (total_fare_bdt >= 0),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  unique(user_id, request_id)
);
create index if not exists bookings_owner_idx on public.bookings(user_id,created_at desc);
create table if not exists public.trip_seats (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id),
  seat_code text not null,
  booking_id uuid references public.bookings(id),
  unique(trip_id,seat_code)
);
create table if not exists public.booking_passengers (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  passenger_order integer not null check (passenger_order between 1 and 4),
  passenger_name text not null check (char_length(trim(passenger_name)) between 2 and 80),
  unique(booking_id,passenger_order)
);
create table if not exists public.booking_seats (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  trip_seat_id uuid not null references public.trip_seats(id),
  passenger_id uuid not null references public.booking_passengers(id),
  unique(booking_id, trip_seat_id),
  unique(booking_id,passenger_id)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  body text not null check (char_length(body) between 1 and 2000),
  image_path text,
  created_at timestamptz not null default now()
);
create index if not exists posts_pagination_idx on public.posts(created_at desc,id desc);
create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.post_comments(post_id,created_at,id);
create table if not exists public.post_reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  reaction text not null check (reaction in ('LIKE','DISLIKE')),
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);
create table if not exists public.post_ratings (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  stars int not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);

-- Do not grant blanket schema write to anon/authenticated. Review RLS in DRAFT_rls.sql first.
