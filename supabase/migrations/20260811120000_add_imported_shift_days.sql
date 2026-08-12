-- Aggregates raw gig rows into one row per platform per local calendar day.
--
-- Two reasons this lives in the database rather than the client:
--   1. A gig is a single trip. A driver logs dozens per shift, so returning raw
--      rows would flood the app with entries that no downstream analytic can
--      interpret as work sessions.
--   2. PostgREST caps a response at `max_rows`. Aggregating first keeps the
--      payload small enough that a long history does not get truncated.
--
-- The local day boundary depends on where the driver is, which the database
-- cannot know, so the caller passes its own zone. Anything unparseable falls
-- back to UTC rather than raising.
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
  resolved_tz text := coalesce(nullif(trim(tz_name), ''), 'UTC');
begin
  begin
    perform (now() at time zone resolved_tz);
  exception
    when others then
      resolved_tz := 'UTC';
  end;

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
  'One aggregated shift per platform per local calendar day for the calling user.';

-- security invoker keeps row level security on earnings_entries in force, so
-- the explicit user_id predicate above is defence in depth rather than the
-- only thing separating one driver''s earnings from another''s.
revoke all on function public.imported_shift_days(text) from public;
grant execute on function public.imported_shift_days(text) to authenticated;
