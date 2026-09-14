Admin features — overview

> **Ships, but only for platform admins.** `app.dart` constructs a
> `SupabaseAdminRepository` whenever `BackendConfig.isConfigured`, and the
> dashboard is handed to `AppShell` only once `is_platform_admin()` has returned
> true — a check that fails closed on an offline or erroring backend. A
> configured release build therefore does expose this to an owner account.
>
> The two defects this note used to carry are both gone:
>
> 1. **The three missing RPCs are no longer called.** `SupabaseAdminRepository`
>    calls exactly `is_platform_admin`, `admin_dashboard_overview`,
>    `admin_list_users` and `admin_set_user_cloud_access`, all four of which
>    `20260814150000_create_admin_control_plane.sql` defines.
> 2. **`loadUserDetail` no longer exists**, so neither does its fallback that
>    answered with the first user in the table instead of the one requested.
>
> `MemoryAdminRepository` has also been removed; there is no in-memory fallback
> and no unconditional debug grant.

Purpose
- Provide platform owners a lightweight dashboard to monitor drivers, imports, and account status and to enable/disable cloud access for users.

UI (existing)
- `lib/features/admin/presentation/admin_dashboard_screen.dart`
  - Overview grid: drivers, completed shifts, connected accounts, 30-day profit.
  - Platform health panel: failed imports in last 24h.
  - Users list: search, filter (All / Active / Paused), per-user card with metrics and a Cloud access switch.
  - Actions: refresh, pause/restore cloud access with confirmation dialog and snackbar feedback.

Granting admin — done in Supabase, never in the app
- There is no in-app path to make someone an owner, by design. The only
  promotion route is `public.promote_platform_owner(owner_email text)`, which is
  `revoke`d from `public` and granted to `service_role` alone — an authenticated
  app session cannot execute it however it is called.
- Run it from the Supabase SQL editor (or any service-role connection) against
  an account that has already signed up:

  ```sql
  select public.promote_platform_owner('you@example.com');
  ```

  It raises `No account exists for that email` rather than creating anything, so
  the account has to exist first.
- Roles live in `public.app_user_roles`, which has RLS on and **no policy at
  all**. No client can read or write it; the app only ever asks the boolean
  `is_platform_admin()`. A driver's role never enters the UI or auth metadata,
  so it cannot be edited from a session.
- To revoke: `update public.app_user_roles set role = 'user' where user_id = '…';`
  Also service-role work — there is deliberately no button for it.

Backend / API (Supabase RPC)
- `is_platform_admin()`
  - Purpose: quick yes/no whether current account can access admin UI.
  - Usage: `SupabaseAdminRepository.canAccessAdmin()` returns `true|false`.
- `admin_dashboard_overview()`
  - Purpose: single-row overview of platform metrics (drivers, active_drivers, shifts, connected_accounts, failed_syncs, profit_30d).
  - Usage: `SupabaseAdminRepository.loadOverview()` -> `AdminOverview.fromJson(...)`.
- `admin_list_users(search_text, limit_count, offset_count, status_filter)`
  - Purpose: one page of drivers, plus `total` for the whole matching set.
    Returns `{"total": n, "rows": [...]}`. `status_filter` is `active`,
    `suspended` or null, and an unrecognised value raises rather than being
    ignored. Replaced the three-argument version, which was dropped rather than
    overloaded — two candidates taking the same named arguments would make every
    call ambiguous.
  - Usage: `SupabaseAdminRepository.loadUsers(query:, filter:, limit:, offset:)`
    -> `AdminUserPage`.
- `admin_set_user_cloud_access(target_user_id, enabled)`
  - Purpose: toggle a user's cloud sync/access state (active/paused). Refuses an
    owner's own account and any other owner's, and writes an audit row on
    success.
  - Usage: `SupabaseAdminRepository.setCloudAccess(userId:, enabled:)`.
- `admin_recent_actions(limit_count)`
  - Purpose: the access-change log, newest first, for the dashboard's trail.
  - Usage: `SupabaseAdminRepository.loadRecentActions()` -> `List<AdminAction>`.

Audit trail
- `public.admin_actions` records every pause and restore: who did it, to whom,
  and when. RLS is on with no policy, so it is reachable only through
  `admin_recent_actions()` and cannot be edited or deleted from any client — an
  audit trail the actor can rewrite is not one.
- Both email addresses are copied into the row rather than joined at read time,
  and the two foreign keys are `on delete set null`. The record therefore
  survives either account being deleted, which is exactly when it matters.

Local/dev fallback
- There is none, deliberately. An unconfigured build gets a null repository and
  no admin entry point at all.
- The seeded `MemoryAdminRepository` was removed: it meant the real Supabase
  path was never exercised, which is how the two defects above survived. Test
  coverage injects a fake through `KeeprateApp.adminRepository` instead, so the
  production wiring has no debug-only branch in it.

Remaining gaps
- Bulk actions (pause many drivers at once) are deliberately not built. Cutting
  off one driver's sync is a decision worth making one at a time.
- CSV export of the driver list is not implemented.
- The overview counts are computed per request. At a few thousand drivers the
  lateral joins in `admin_list_users` will want an index on `shifts(user_id)`
  before this stays snappy.

How to run locally
1. Point the app at a configured Supabase project (see the README's dart-define
   block). Without one there is no admin repository and no entry point.
2. Grant your account owner rights: `select public.promote_platform_owner('you@example.com');`
   That function is granted to `service_role` only, so run it from the SQL
   editor or a service-role connection, never from the client.
3. Sign in as that account and open Admin via Settings. It appears only after
   `is_platform_admin()` returns true.
4. Use the search, filters, and toggle switches to validate behavior. Pausing a
   driver should appear in the Access changes trail at the foot of the screen.

Tests
- `test/admin_dashboard_test.dart` covers the entry point being hidden from
  normal accounts, the owner path from Settings, server-side status filtering,
  paging past the first 50 rows, the audit trail after a pause, and payload
  parsing for both the paged and the legacy list shapes.
- The fake repository applies the search, filter and window itself, so a
  regression that filtered on the client — which would quietly mean "the paused
  drivers on this page" — fails the suite rather than passing it.
