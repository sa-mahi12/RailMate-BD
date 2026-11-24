-- P42 hardening, part 2 — idempotent reports (2026-11-25)
--
-- The clients report with an upsert, and PostgREST only resolves a conflict
-- when the client names the constraint (`on_conflict=...`). A plain insert on
-- the shipped +29 build therefore hit the unique constraint `(post_id,
-- reporter_id)` and failed with a 409 instead of recording the second report.
--
-- Rather than require a new APK for a one-line query option, the database
-- resolves it: a second report for the same reporter and target updates the
-- existing row in place (reason/details/status), keeping the original
-- `created_at` so the owner can still see when the report was first filed.
-- Nothing is deleted and no policy changes.

begin;

create or replace function public.report_upsert_once()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_table_name = 'post_reports' then
    update public.post_reports r
       set reason = new.reason,
           details = new.details,
           status = 'open'
     where r.post_id = new.post_id
       and r.reporter_id = new.reporter_id;
  elsif tg_table_name = 'user_reports' then
    update public.user_reports r
       set reason = new.reason,
           details = new.details,
           status = 'open'
     where r.reported_user_id = new.reported_user_id
       and r.reporter_id = new.reporter_id;
  else
    return new;
  end if;

  if found then
    -- The row already existed: this insert becomes an update, so no duplicate
    -- is attempted and no constraint error reaches the client.
    return null;
  end if;
  return new;
end;
$function$;

drop trigger if exists post_reports_upsert_once on public.post_reports;
create trigger post_reports_upsert_once
  before insert on public.post_reports
  for each row execute function public.report_upsert_once();

drop trigger if exists user_reports_upsert_once on public.user_reports;
create trigger user_reports_upsert_once
  before insert on public.user_reports
  for each row execute function public.report_upsert_once();

commit;
