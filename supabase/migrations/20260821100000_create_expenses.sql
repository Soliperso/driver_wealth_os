-- Costs that belong to the business rather than to a single shift.
--
-- A shift carries one `direct_expenses` scalar: what was spent while driving
-- that day. That leaves a brake job, an insurance premium, a phone bill and a
-- car payment with nowhere to go — every one of them a real cost of the work,
-- and every one of them missing from the driver's total. It also made a tax
-- year impossible to assemble, because Schedule C wants costs by category and
-- the app had exactly one.
--
-- Shaped like `public.shifts` on purpose: same composite key on (user_id, id),
-- same client-minted id so sync stays a plain upsert, same updated_at clock for
-- last-write-wins, same tombstone column so a delete on one phone is not undone
-- by another phone's next push.

create table if not exists public.expenses (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  amount numeric(12, 2) not null default 0,
  -- Free text rather than an enum: the app owns the category list and adding a
  -- Schedule C line should not need a migration and a deploy in lockstep. An
  -- unrecognised value decodes to "other" on the client.
  category text not null default 'other',
  incurred_on timestamptz not null,
  note text not null default '',
  -- The device-local path to a receipt photo. The image itself is deliberately
  -- not uploaded: a receipt can carry a card number and a home address, and
  -- storing every driver's shoebox is a liability with no product benefit. A
  -- second device shows the entry without the photo.
  receipt_path text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint expenses_non_negative check (amount >= 0)
);

-- Pulls are "everything that changed since my cursor", so that is the index.
create index if not exists expenses_user_updated_at_idx
  on public.expenses (user_id, updated_at desc);

-- The tax screen reads a year at a time.
create index if not exists expenses_user_incurred_on_idx
  on public.expenses (user_id, incurred_on desc);

alter table public.expenses enable row level security;

drop policy if exists "Drivers manage their expenses" on public.expenses;
create policy "Drivers manage their expenses"
  on public.expenses for all to authenticated
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

-- Same trigger the other driver tables use, so the sync cursor is set by the
-- server clock rather than by whatever the device believes the time is.
drop trigger if exists expenses_touch_updated_at on public.expenses;
create trigger expenses_touch_updated_at
  before update on public.expenses
  for each row execute function public.touch_updated_at();

-- Account deletion removes these along with everything else. The cascade above
-- covers it, but `delete_my_account` lists its tables explicitly so a table
-- added without a cascade cannot outlive the account — keep this in step.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.app_user_roles
    where user_id = uid and role = 'admin'
  ) then
    raise exception 'An administrator cannot delete their own account'
      using errcode = '42501';
  end if;

  delete from public.shifts where user_id = uid;
  delete from public.expenses where user_id = uid;
  delete from public.driver_preferences where user_id = uid;
  delete from public.income_connections where user_id = uid;
  delete from public.work_accounts where user_id = uid;
  delete from public.earnings_entries where user_id = uid;
  delete from public.sync_jobs where user_id = uid;
  delete from public.app_user_roles where user_id = uid;

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
