-- Reject anything that is not a real IANA zone name.
--
-- The previous guard could not catch the bug it was written for. It tested the
-- zone with `perform (now() at time zone resolved_tz)` and fell back to UTC on
-- an exception — but `UTC-05:00` does not raise. Postgres has no zone by that
-- name, so it parses it as a POSIX specification instead, and in POSIX a
-- positive offset means *west* of Greenwich: the opposite of ISO 8601. So
-- `UTC-05:00` silently resolved to UTC+5, ten hours from the intended zone,
-- and every imported day for a New York driver bucketed onto the wrong date.
--
-- Checking membership in pg_timezone_names is the only test that distinguishes
-- a genuine zone from a plausible-looking POSIX string.
create or replace function public.imported_shift_days(tz_name text default 'UTC')
returns table (
  platform text,
  local_day date,
  gross numeric,
  hours numeric,
  miles numeric,
  last_activity_at timestamptz,
  entry_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  requested_tz text := coalesce(nullif(trim(tz_name), ''), 'UTC');
  resolved_tz text;
begin
  select n.name into resolved_tz
  from pg_catalog.pg_timezone_names n
  where n.name = requested_tz;

  -- UTC rather than a fixed offset: being a few hours out is a visible,
  -- explicable error, whereas a POSIX offset is silently inverted.
  if resolved_tz is null then
    resolved_tz := 'UTC';
  end if;

  return query
  select
    e.provider::text as platform,
    ((coalesce(e.ended_at, e.started_at)) at time zone resolved_tz)::date as local_day,
    sum(e.earnings_amount)::numeric as gross,
    sum(coalesce(e.duration_hours, 0))::numeric as hours,
    sum(coalesce(e.distance_miles, 0))::numeric as miles,
    max(coalesce(e.ended_at, e.started_at)) as last_activity_at,
    count(*)::bigint as entry_count
  from public.earnings_entries e
  where e.user_id = (select auth.uid())
    and e.source_kind = 'gig'
    -- Cancelled trips are not earnings.
    and lower(e.status) not in ('cancelled', 'canceled')
    and coalesce(e.ended_at, e.started_at) is not null
  group by 1, 2
  order by 2 desc, 1 asc;
end;
$$;

comment on function public.imported_shift_days(text) is
  'One aggregated shift per platform per local calendar day for the calling user. Requires an IANA zone name; anything else falls back to UTC.';

revoke all on function public.imported_shift_days(text) from public;
grant execute on function public.imported_shift_days(text) to authenticated;
