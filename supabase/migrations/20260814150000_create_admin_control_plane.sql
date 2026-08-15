-- Private application roles and the owner control plane.
--
-- Roles live in a table the client cannot read or edit. The Flutter app asks
-- only the boolean `is_platform_admin()` question, so a normal driver's role
-- never needs to enter the UI or user-editable auth metadata.

create table if not exists public.app_user_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'user' check (role in ('user', 'admin')),
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.app_user_roles enable row level security;

-- No table policy is intentional. Application clients cannot enumerate roles.
-- All access goes through the narrow security-definer functions below.

create or replace function public.create_default_app_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_user_roles (user_id, role, status)
  values (new.id, 'user', 'active')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_create_default_app_role on auth.users;
create trigger auth_user_create_default_app_role
  after insert on auth.users
  for each row execute function public.create_default_app_role();

-- Existing accounts predate the trigger and must receive the same safe default.
insert into public.app_user_roles (user_id, role, status)
select id, 'user', 'active'
from auth.users
on conflict (user_id) do nothing;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.app_user_roles
    where user_id = (select auth.uid())
      and role = 'admin'
      and status = 'active'
  );
$$;

create or replace function public.has_active_cloud_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.app_user_roles
    where user_id = (select auth.uid())
      and status = 'active'
  );
$$;

revoke all on function public.is_platform_admin() from public;
revoke all on function public.has_active_cloud_access() from public;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.has_active_cloud_access() to authenticated;

-- This is the only role-promotion path. It is deliberately unavailable to an
-- authenticated app session and must be run by the project owner through the
-- SQL editor or a service-role deployment.
create or replace function public.promote_platform_owner(owner_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
begin
  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(owner_email))
  limit 1;

  if target_user_id is null then
    raise exception 'No account exists for that email';
  end if;

  insert into public.app_user_roles (user_id, role, status, updated_at)
  values (target_user_id, 'admin', 'active', now())
  on conflict (user_id) do update
    set role = 'admin', status = 'active', updated_at = now();
end;
$$;

revoke all on function public.promote_platform_owner(text) from public;
grant execute on function public.promote_platform_owner(text) to service_role;

create or replace function public.admin_dashboard_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'drivers', (
      select count(*)
      from public.app_user_roles
      where role = 'user'
    ),
    'active_drivers', (
      select count(*)
      from public.app_user_roles
      where role = 'user' and status = 'active'
    ),
    'shifts', (
      select count(*) from public.shifts where deleted_at is null
    ),
    'connected_accounts', (
      select count(*) from public.work_accounts where status = 'connected'
    ),
    'failed_syncs', (
      select count(*)
      from public.sync_jobs
      where status = 'failed' and started_at >= now() - interval '24 hours'
    ),
    'profit_30d', (
      select coalesce(
        sum(gross - direct_expenses - (miles * vehicle_cost_per_mile)),
        0
      )
      from public.shifts
      where deleted_at is null
        and completed_at >= now() - interval '30 days'
    )
  );
end;
$$;

create or replace function public.admin_list_users(
  search_text text default null,
  limit_count integer default 100,
  offset_count integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(driver_row)), '[]'::jsonb)
  into result
  from (
    select
      u.id,
      u.email,
      p.driver_name,
      u.created_at,
      u.last_sign_in_at,
      r.status,
      coalesce(s.shift_count, 0) as shift_count,
      coalesce(s.total_profit, 0) as total_profit,
      coalesce(a.work_account_count, 0) as work_account_count
    from auth.users u
    join public.app_user_roles r on r.user_id = u.id and r.role = 'user'
    left join public.driver_preferences p on p.user_id = u.id
    left join lateral (
      select
        count(*) as shift_count,
        coalesce(
          sum(gross - direct_expenses - (miles * vehicle_cost_per_mile)),
          0
        ) as total_profit
      from public.shifts
      where user_id = u.id and deleted_at is null
    ) s on true
    left join lateral (
      select count(*) as work_account_count
      from public.work_accounts
      where user_id = u.id and status <> 'disconnected'
    ) a on true
    where search_text is null
      or trim(search_text) = ''
      or coalesce(p.driver_name, '') ilike '%' || trim(search_text) || '%'
      or coalesce(u.email, '') ilike '%' || trim(search_text) || '%'
    order by u.created_at desc
    limit least(greatest(limit_count, 1), 200)
    offset greatest(offset_count, 0)
  ) driver_row;

  return result;
end;
$$;

create or replace function public.admin_set_user_cloud_access(
  target_user_id uuid,
  enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  if target_user_id = (select auth.uid()) then
    raise exception 'An owner cannot disable their own access';
  end if;

  if exists (
    select 1 from public.app_user_roles
    where user_id = target_user_id and role = 'admin'
  ) then
    raise exception 'Owner access cannot be changed here';
  end if;

  update public.app_user_roles
  set status = case when enabled then 'active' else 'suspended' end,
      updated_at = now()
  where user_id = target_user_id and role = 'user';

  if not found then
    raise exception 'Driver account not found';
  end if;
end;
$$;

revoke all on function public.admin_dashboard_overview() from public;
revoke all on function public.admin_list_users(text, integer, integer) from public;
revoke all on function public.admin_set_user_cloud_access(uuid, boolean) from public;
grant execute on function public.admin_dashboard_overview() to authenticated;
grant execute on function public.admin_list_users(text, integer, integer) to authenticated;
grant execute on function public.admin_set_user_cloud_access(uuid, boolean) to authenticated;

-- Suspended accounts retain their on-device records but cannot read or write
-- cloud records. Recreate the existing owner policies with the access check.
drop policy if exists "Drivers manage their shifts" on public.shifts;
create policy "Drivers manage their shifts"
  on public.shifts for all to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  )
  with check (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );

drop policy if exists "Drivers manage their freedom goal" on public.freedom_goals;
create policy "Drivers manage their freedom goal"
  on public.freedom_goals for all to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  )
  with check (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );

drop policy if exists "Users manage their preferences" on public.driver_preferences;
create policy "Users manage their preferences"
  on public.driver_preferences for all to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  )
  with check (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );

drop policy if exists "Users read their income connection" on public.income_connections;
create policy "Users read their income connection"
  on public.income_connections for select to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );

drop policy if exists "Users read their work accounts" on public.work_accounts;
create policy "Users read their work accounts"
  on public.work_accounts for select to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );

drop policy if exists "Users read their earnings" on public.earnings_entries;
create policy "Users read their earnings"
  on public.earnings_entries for select to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );

drop policy if exists "Users read their sync history" on public.sync_jobs;
create policy "Users read their sync history"
  on public.sync_jobs for select to authenticated
  using (
    (select auth.uid()) = user_id
    and public.is_permanent_user()
    and public.has_active_cloud_access()
  );
