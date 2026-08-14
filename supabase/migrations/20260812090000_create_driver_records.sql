-- Server-side storage for what the product is actually about.
--
-- Until now the only tables were the Argyle import pipeline. Every manually
-- entered shift, every hand-added fuel/toll/parking cost, the freedom goal and
-- the driver's name lived in SharedPreferences and nowhere else, so
-- uninstalling the app destroyed the driver's entire financial history.
--
-- These tables are written by the client, unlike the import tables which are
-- written only by service-role edge functions. They therefore need full owner
-- policies rather than the read-only ones used there.

-- One row per shift, keyed by the id the app already generates
-- (`manual-<micros>`, `tracked-<micros>`, `imported:<platform>:<date>`).
-- Reusing the client id rather than minting a server one keeps sync a plain
-- upsert and makes the imported-shift dedupe work identically on both sides.
create table if not exists public.shifts (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  platform text not null,
  gross numeric(12, 2) not null default 0,
  hours numeric(10, 4) not null default 0,
  miles numeric(10, 2) not null default 0,
  direct_expenses numeric(12, 2) not null default 0,
  vehicle_cost_per_mile numeric(10, 4) not null default 0,
  completed_at timestamptz not null,
  source text not null default 'manual',
  -- Last-write-wins needs a comparable clock on every record.
  updated_at timestamptz not null default now(),
  -- A tombstone rather than a hard delete: without one, a delete on phone A
  -- would be undone by phone B's next push, which still has the row.
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint shifts_non_negative check (
    gross >= 0
    and hours >= 0
    and miles >= 0
    and direct_expenses >= 0
    and vehicle_cost_per_mile >= 0
  )
);

-- Pulls are "everything that changed since my cursor", so the cursor column is
-- the one that has to be indexed.
create index if not exists shifts_user_updated_at_idx
  on public.shifts (user_id, updated_at desc);

-- Exactly one goal per driver, matching the product: the app deliberately
-- offers a single Freedom goal rather than a list.
create table if not exists public.freedom_goals (
  user_id uuid primary key references auth.users (id) on delete cascade,
  id text not null,
  title text not null,
  target_amount numeric(12, 2) not null,
  starting_amount numeric(12, 2) not null default 0,
  allocation_rate numeric(5, 4) not null,
  goal_created_at timestamptz not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint freedom_goals_sane check (
    target_amount > 0
    and starting_amount >= 0
    and starting_amount <= target_amount
    and allocation_rate > 0
    and allocation_rate <= 1
  )
);

-- driver_preferences already existed but nothing ever read or wrote it: the
-- daily goal and vehicle rate it was built for were kept in SharedPreferences.
-- These columns give it the rest of what the app actually stores.
alter table public.driver_preferences
  add column if not exists driver_name text,
  add column if not exists theme_mode text not null default 'system',
  add column if not exists updated_at timestamptz not null default now();

alter table public.shifts enable row level security;
alter table public.freedom_goals enable row level security;

-- True for a driver who signed in with an email code, false for an anonymous
-- session.
--
-- `to authenticated` is not enough on its own: an anonymous Supabase session
-- also carries the `authenticated` role, differing only by the `is_anonymous`
-- JWT claim. Anonymous sign-in is disabled in config.toml, but that is an auth
-- setting a future change could flip; this makes the database itself refuse,
-- which is what the security advisor is actually asking for.
--
-- Coalesced to false so a token minted before the claim existed is treated as
-- a real user rather than locked out.
create or replace function public.is_permanent_user()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    ((select auth.jwt() ->> 'is_anonymous')::boolean) is not true,
    true
  );
$$;

drop policy if exists "Drivers manage their shifts" on public.shifts;
create policy "Drivers manage their shifts"
  on public.shifts
  for all
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user())
  with check ((select auth.uid()) = user_id and public.is_permanent_user());

drop policy if exists "Drivers manage their freedom goal" on public.freedom_goals;
create policy "Drivers manage their freedom goal"
  on public.freedom_goals
  for all
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user())
  with check ((select auth.uid()) = user_id and public.is_permanent_user());

-- The pre-existing policies were written without a role clause, so they
-- extended to anonymous users. Anonymous sign-in is now disabled outright, but
-- the policies are narrowed too rather than relying on that alone.
drop policy if exists "Users manage their preferences" on public.driver_preferences;
create policy "Users manage their preferences"
  on public.driver_preferences
  for all
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user())
  with check ((select auth.uid()) = user_id and public.is_permanent_user());

drop policy if exists "Users read their income connection" on public.income_connections;
create policy "Users read their income connection"
  on public.income_connections
  for select
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user());

drop policy if exists "Users read their work accounts" on public.work_accounts;
create policy "Users read their work accounts"
  on public.work_accounts
  for select
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user());

drop policy if exists "Users read their earnings" on public.earnings_entries;
create policy "Users read their earnings"
  on public.earnings_entries
  for select
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user());

drop policy if exists "Users read their sync history" on public.sync_jobs;
create policy "Users read their sync history"
  on public.sync_jobs
  for select
  to authenticated
  using ((select auth.uid()) = user_id and public.is_permanent_user());

-- `updated_at` is the sync cursor, so it cannot be left to the client to set
-- honestly. A trigger makes the server's clock authoritative.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists shifts_touch_updated_at on public.shifts;
create trigger shifts_touch_updated_at
  before insert or update on public.shifts
  for each row execute function public.touch_updated_at();

drop trigger if exists freedom_goals_touch_updated_at on public.freedom_goals;
create trigger freedom_goals_touch_updated_at
  before insert or update on public.freedom_goals
  for each row execute function public.touch_updated_at();

drop trigger if exists driver_preferences_touch_updated_at on public.driver_preferences;
create trigger driver_preferences_touch_updated_at
  before insert or update on public.driver_preferences
  for each row execute function public.touch_updated_at();
