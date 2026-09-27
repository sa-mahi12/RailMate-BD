-- DRAFT / NOT APPLIED. This is a design starting point, NOT TESTED on a real Postgres instance.
-- Invoker runs as service_role from a trusted hosted Edge Function; deny execute to anon/authenticated.
-- Exact transaction behavior/constraint names must be validated in a separate hosted staging project.
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
  -- Lock actual seat rows in globally stable order. A loop counts ALL requested rows.
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
  update public.trip_seats set booking_id=v_booking_id
    where trip_id=p_trip_id and seat_code=any(p_seat_codes) and booking_id is null;
  get diagnostics v_count = row_count;
  if v_count <> v_n then raise exception 'CONCURRENT_CONFLICT'; end if;
  return v_booking_id;
end; $$;
revoke all on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) from public,anon,authenticated;
grant execute on function public.book_trip_service(uuid,uuid,uuid,jsonb,text[]) to service_role;

create or replace function public.cancel_booking_service(p_user_id uuid,p_booking_id uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
 v_booking public.bookings%rowtype;
begin
 select * into v_booking from public.bookings where id=p_booking_id and user_id=p_user_id for update;
 if not found then raise exception 'NOT_FOUND'; end if;
 if v_booking.status='CANCELLED' then return true; end if;
 update public.bookings set status='CANCELLED',cancelled_at=now() where id=p_booking_id;
 update public.trip_seats set booking_id=null where booking_id=p_booking_id;
 return true;
end; $$;
revoke all on function public.cancel_booking_service(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cancel_booking_service(uuid,uuid) to service_role;
-- Before live application: check actual grants, service-role exposure, SQL injection, RLS and two-session concurrency test.
