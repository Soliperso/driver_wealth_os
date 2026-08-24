-- In-app account deletion.
--
-- Both the App Store and Google Play require an app that lets people create an
-- account to let them delete it from inside the app. Signing out only wiped the
-- device; the account and every shift under it stayed on the server with no way
-- for the driver to remove them. That is a hard store rejection as well as a
-- reasonable thing for someone to want.
--
-- Every table that holds driver data references auth.users with
-- `on delete cascade` — shifts, driver_preferences, income_connections,
-- work_accounts, earnings_entries, sync_jobs and app_user_roles — so removing
-- the auth row removes the rest. The deletes are still written out explicitly
-- below: a table added later without a cascade would otherwise silently outlive
-- the account it belonged to.

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

  -- An administrator deleting themselves through the app would leave the
  -- control plane short an admin, with no way to appoint another except the
  -- service role. `promote_platform_owner` is the deliberate route in; this is
  -- deliberately not the route out.
  if exists (
    select 1 from public.app_user_roles
    where user_id = uid and role = 'admin'
  ) then
    raise exception 'An administrator cannot delete their own account'
      using errcode = '42501';
  end if;

  delete from public.shifts where user_id = uid;
  delete from public.driver_preferences where user_id = uid;
  delete from public.income_connections where user_id = uid;
  delete from public.work_accounts where user_id = uid;
  delete from public.earnings_entries where user_id = uid;
  delete from public.sync_jobs where user_id = uid;
  delete from public.app_user_roles where user_id = uid;

  -- Last, and the one that matters: while this row exists the address can
  -- still be signed in to.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

comment on function public.delete_my_account() is
  'Permanently deletes the calling user''s account and all of their data. '
  'Required by App Store and Play Store policy for apps offering accounts.';
