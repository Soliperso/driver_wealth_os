-- Idempotency for inbound provider webhooks.
--
-- The webhook verifies an HMAC but had no notion of having already handled an
-- event. Two consequences, both real:
--
--   * A captured request stayed replayable forever, and each replay triggered
--     another full sync against a service-role write path.
--   * Argyle retries on any non-2xx, and the function returned 500 for every
--     failure — so one transient upstream error produced a retry storm, each
--     retry re-downloading the driver's entire gig history.
--
-- Recording the event id under a unique constraint makes the second delivery a
-- cheap, obvious no-op.
create table if not exists public.webhook_events (
  provider text not null,
  event_id text not null,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);

-- Written only by service-role edge functions. RLS is on with no policy at
-- all, which is what denies every client: there is nothing here a driver needs.
alter table public.webhook_events enable row level security;

-- Supports the retention sweep below.
create index if not exists webhook_events_received_at_idx
  on public.webhook_events (received_at);

-- Both of these grow forever otherwise — one row per webhook delivery, and the
-- webhook fires per gig. Kept long enough to outlive any provider retry window
-- and to debug a bad day, and no longer.
create or replace function public.prune_sync_history(retain interval default '30 days')
returns void
language sql
security invoker
set search_path = ''
as $$
  with pruned_events as (
    delete from public.webhook_events
    where received_at < now() - retain
    returning 1
  ),
  pruned_jobs as (
    delete from public.sync_jobs
    where started_at < now() - retain
    returning 1
  )
  select;
$$;

comment on function public.prune_sync_history(interval) is
  'Deletes webhook dedupe rows and sync job history older than the retention window. Schedule with pg_cron, or call periodically.';
