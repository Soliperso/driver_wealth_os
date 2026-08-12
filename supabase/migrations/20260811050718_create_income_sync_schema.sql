create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table public.driver_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_goal numeric(10, 2) not null default 250 check (daily_goal > 0 and daily_goal <= 100000),
  vehicle_cost_per_mile numeric(8, 4) not null default 0.30 check (vehicle_cost_per_mile >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.income_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  argyle_user_id text not null unique,
  environment text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.work_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  external_account_id text not null,
  provider text not null,
  display_name text not null,
  category text,
  status text not null default 'connected' check (status in ('connected', 'syncing', 'needs_attention', 'disconnected')),
  last_synced_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, external_account_id)
);

create table public.earnings_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  work_account_id uuid not null references public.work_accounts(id) on delete cascade,
  source_kind text not null default 'gig' check (source_kind in ('gig', 'paystub', 'manual')),
  external_id text not null,
  provider text not null,
  status text not null default 'completed',
  earning_type text,
  currency text not null default 'USD',
  earnings_amount numeric(12, 2) not null default 0,
  customer_price numeric(12, 2),
  platform_fees numeric(12, 2),
  tips numeric(12, 2),
  bonus numeric(12, 2),
  duration_hours numeric(10, 4),
  distance_miles numeric(10, 3),
  started_at timestamptz,
  ended_at timestamptz,
  source_updated_at timestamptz,
  source_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, source_kind, external_id)
);

create table public.sync_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null default 'argyle',
  status text not null default 'running' check (status in ('running', 'succeeded', 'failed')),
  records_processed integer not null default 0,
  error_message text,
  started_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz
);

create index earnings_entries_user_started_idx
  on public.earnings_entries (user_id, started_at desc);
create index work_accounts_user_idx on public.work_accounts (user_id);
create index sync_jobs_user_started_idx on public.sync_jobs (user_id, started_at desc);

create trigger driver_preferences_set_updated_at
before update on public.driver_preferences
for each row execute function public.set_updated_at();

create trigger income_connections_set_updated_at
before update on public.income_connections
for each row execute function public.set_updated_at();

create trigger work_accounts_set_updated_at
before update on public.work_accounts
for each row execute function public.set_updated_at();

create trigger earnings_entries_set_updated_at
before update on public.earnings_entries
for each row execute function public.set_updated_at();

alter table public.driver_preferences enable row level security;
alter table public.income_connections enable row level security;
alter table public.work_accounts enable row level security;
alter table public.earnings_entries enable row level security;
alter table public.sync_jobs enable row level security;

create policy "Users manage their preferences"
on public.driver_preferences for all
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users read their income connection"
on public.income_connections for select
using ((select auth.uid()) = user_id);

create policy "Users read their work accounts"
on public.work_accounts for select
using ((select auth.uid()) = user_id);

create policy "Users read their earnings"
on public.earnings_entries for select
using ((select auth.uid()) = user_id);

create policy "Users read their sync history"
on public.sync_jobs for select
using ((select auth.uid()) = user_id);
