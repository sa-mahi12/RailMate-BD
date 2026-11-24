# P42 moderation (reports only)

RailMate BD is a demonstration prototype with a public Journey Board. P42 adds
**reporting**, not an automated moderation system. This note says exactly what
happens to a report so nothing is overstated.

## What a report is

* `public.post_reports(post_id, reporter_id, reason, details, status, created_at)`
* `public.user_reports(reported_user_id, reporter_id, reason, details, status, created_at)`
* Reasons are constrained to the codes the clients offer:
  * post: `spam`, `harassment`, `misinformation`, `unsafe_media`, `other`
  * profile: `spam`, `harassment`, `impersonation`, `other`
* One row per reporter per target (`unique (target, reporter_id)`); a second
  report updates the first. The database resolves that update itself
  (`20261125000002_p42_report_upsert.sql`), so a client that simply re-inserts
  still records the new reason instead of erroring.
* `details` is optional, ≤ 500 characters.
* A profile cannot be reported by its owner (`user_reports_no_self`), and an
  author cannot report their own post (`post_reports_no_self`,
  `20261125000001_p42_hardening.sql`).
* Reporters see only their own rows (RLS `reporter_id = auth.uid()`). The
  reported author never sees them, and the public site never queries them.

## What happens next (owner procedure)

There is no admin UI and no automatic action. The project owner reviews rows
with the service role:

```sql
-- open reports, newest first
select r.created_at, r.reason, r.details, p.body
from public.post_reports r
join public.posts p on p.id = r.post_id
where r.status = 'open'
order by r.created_at desc;

-- mark reviewed / dismissed
update public.post_reports set status = 'reviewed' where id = '<id>';
```

The owner then either does nothing, or deletes the post row (cascades the
attachments) and, if the Storage object should go too, removes it from the
`post-media` bucket. Deleting a post never changes anyone's rating or any
personal score — post ratings are per-post values, and P42 introduces no
person-level reputation.

## What a report is **not**

* Not a rating. Stars rate a *post*; reports never feed a score.
* Not an automatic takedown. Nothing is hidden by the act of reporting.
* Not a private message channel. `details` is read by the owner, not by the
  reported author.

## Rate limits

`enforce_board_rate_limit` caps new posts at 10 and comments at 30 per author
per 10 minutes. That is an abuse guard, not moderation: it slows flooding and
never silently rewrites or deletes content.
