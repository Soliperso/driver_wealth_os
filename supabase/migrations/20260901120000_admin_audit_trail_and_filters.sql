-- Completes the owner control plane: a durable audit trail for access changes,
-- server-side status filtering, and a total count so the dashboard can page.
--
-- Pausing a driver's cloud access stops their sync. That is the most
-- consequential thing an owner can do to someone else's account, and until now
-- it left no record of who did it or when. Everything below exists so that
-- action is traceable and so the list of drivers it is performed from stops
-- being capped at the first hundred rows.

create table if not exists public.admin_actions (
  id bigint generated always as identity primary key,
  -- Nullable with `on delete set null` on purpose: the audit trail has to
  -- outlive both accounts. A deleted owner must not erase the record of what
  -- they did, and a deleted driver must not erase the record of it being done.
  actor_user_id uuid references auth.users (id) on delete set null,
  target_user_id uuid references auth.users (id) on delete set null,
  actor_email text,
  target_email text,
  action text not null check (
    action in ('cloud_access_paused', 'cloud_access_restored')
  ),
  created_at timestamptz not null default now()
);

alter table public.admin_actions enable row level security;

-- No table policy, matching `app_user_roles`. The log is reachable only through
-- the security-definer reader below, so no client can enumerate or edit it —
-- an audit trail an actor can rewrite is not an audit trail.

create index if not exists admin_actions_created_at_idx
  on public.admin_actions (created_at desc);

-- The three-argument version has to go rather than gain an overload: the client
-- calls with named arguments, and two candidates that both accept the same
-- three names would make every call ambiguous.
drop function if exists public.admin_list_users(text, integer, integer);

create or replace function public.admin_list_users(
  search_text text default null,
  limit_count integer default 50,
  offset_count integer default 0,
  status_filter text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  needle text := nullif(trim(coalesce(search_text, '')), '');
  wanted text := nullif(trim(coalesce(status_filter, '')), '');
  matched integer;
  page_rows jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  -- Rejected rather than ignored. Silently returning every driver for an
  -- unrecognised filter would show an owner more accounts than they asked to
  -- see and let them act on the wrong one.
  if wanted is not null and wanted not in ('active', 'suspended') then
    raise exception 'Unknown status filter: %', wanted;
  end if;

  with filtered as (
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
    where (
      needle is null
      or coalesce(p.driver_name, '') ilike '%' || needle || '%'
      or coalesce(u.email, '') ilike '%' || needle || '%'
    )
    and (wanted is null or r.status = wanted)
  ),
  page as (
    select *
    from filtered
    order by created_at desc
    -- Coalesced before clamping: a caller that sends an explicit null would
    -- otherwise produce `limit null`, which returns the entire table rather
    -- than one page.
    limit least(greatest(coalesce(limit_count, 50), 1), 200)
    offset greatest(coalesce(offset_count, 0), 0)
  )
  select
    (select count(*) from filtered),
    (
      select coalesce(
        jsonb_agg(to_jsonb(page) order by page.created_at desc),
        '[]'::jsonb
      )
      from page
    )
  into matched, page_rows;

  -- `total` is the size of the whole filtered set, not of this page, so the
  -- dashboard can say "40 of 900" and know whether another page exists.
  return jsonb_build_object('total', matched, 'rows', page_rows);
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
declare
  actor_id uuid := (select auth.uid());
begin
  if not public.is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  if target_user_id = actor_id then
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

  -- Written after the update, so a refused change leaves no entry claiming it
  -- happened. Both addresses are copied in rather than joined at read time:
  -- the whole point of the log is to still answer the question after one of
  -- the accounts has been deleted.
  insert into public.admin_actions (
    actor_user_id, target_user_id, actor_email, target_email, action
  )
  values (
    actor_id,
    target_user_id,
    (select email from auth.users where id = actor_id),
    (select email from auth.users where id = target_user_id),
    case when enabled then 'cloud_access_restored' else 'cloud_access_paused' end
  );
end;
$$;

create or replace function public.admin_recent_actions(
  limit_count integer default 20
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

  select coalesce(jsonb_agg(to_jsonb(entry) order by entry.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      l.id,
      l.action,
      l.created_at,
      l.actor_email,
      l.target_email,
      p.driver_name as target_name
    from public.admin_actions l
    left join public.driver_preferences p on p.user_id = l.target_user_id
    order by l.created_at desc
    limit least(greatest(coalesce(limit_count, 20), 1), 100)
  ) entry;

  return result;
end;
$$;

revoke all on function public.admin_list_users(text, integer, integer, text) from public;
revoke all on function public.admin_recent_actions(integer) from public;
grant execute on function public.admin_list_users(text, integer, integer, text) to authenticated;
grant execute on function public.admin_recent_actions(integer) to authenticated;
