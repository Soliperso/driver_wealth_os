Admin features — overview

> **Not shipping in v1.** `lib/main.dart` supplies no admin repository, so the
> dashboard is unreachable in every build. Two defects have to be fixed first:
>
> 1. **Three RPCs the client calls do not exist.** `admin_get_user_detail`,
>    `admin_list_user_sync_events` and `admin_force_resync_user` are called from
>    `SupabaseAdminRepository` but are defined in no migration. Only
>    `is_platform_admin`, `admin_dashboard_overview`, `admin_list_users` and
>    `admin_set_user_cloud_access` exist.
> 2. **`loadUserDetail` answers with the wrong driver.** Its fallback catches the
>    missing-RPC error and returns `loadUsersPage(query: '', limit: 1, offset: 0).first`
>    — the first user in the table, not the one requested. An owner opening
>    driver B would be shown driver A's email, shift count and profit.
>
> Both survived because `main.dart` handed every debug build a seeded
> `MemoryAdminRepository`, and `app.dart` granted it access unconditionally, so
> the real Supabase path was never once exercised. That shortcut is gone.
>
> The feature code and `20260814150000_create_admin_control_plane.sql` stay in
> the tree. Re-enable by writing the three functions, deleting the fallback, and
> passing a repository from `main.dart` again.

Purpose
- Provide platform owners a lightweight dashboard to monitor drivers, imports, and account status and to enable/disable cloud access for users.

UI (existing)
- `lib/features/admin/presentation/admin_dashboard_screen.dart`
  - Overview grid: drivers, completed shifts, connected accounts, 30-day profit.
  - Platform health panel: failed imports in last 24h.
  - Users list: search, filter (All / Active / Paused), per-user card with metrics and a Cloud access switch.
  - Actions: refresh, pause/restore cloud access with confirmation dialog and snackbar feedback.

Backend / API (Supabase RPC)
- `is_platform_admin()`
  - Purpose: quick yes/no whether current account can access admin UI.
  - Usage: `SupabaseAdminRepository.canAccessAdmin()` returns `true|false`.
- `admin_dashboard_overview()`
  - Purpose: single-row overview of platform metrics (drivers, active_drivers, shifts, connected_accounts, failed_syncs, profit_30d).
  - Usage: `SupabaseAdminRepository.loadOverview()` -> `AdminOverview.fromJson(...)`.
- `admin_list_users(search_text, limit_count, offset_count)`
  - Purpose: paginated user list; supports a free-text query for name/email.
  - Usage: `SupabaseAdminRepository.loadUsers(query: ...)` -> `List<AdminUserSummary>`.
- `admin_set_user_cloud_access(target_user_id, enabled)`
  - Purpose: toggle a user's cloud sync/access state (active/paused).
  - Usage: `SupabaseAdminRepository.setCloudAccess(userId:, enabled:)`.

Local/dev fallback
- `lib/features/admin/application/admin_repository.dart` now contains `MemoryAdminRepository`.
  - Allows running the admin UI without a Supabase backend.
  - Seeded with example users; supports search and toggling cloud access in-memory.
- `lib/app.dart` falls back to `MemoryAdminRepository()` when `BackendConfig.isConfigured` is false.

Gaps & recommended additions
- Paging for `admin_list_users` (UI currently fetches up to 100 rows). Add load-more or infinite scroll.
- Export CSV / bulk actions (e.g., pause many users) — not yet implemented.
- Audit logging for `setCloudAccess` changes (server-side) so owner actions are traceable.
- Unit & widget tests for `AdminDashboardScreen` (smoke + interaction for toggling access).

How to run locally
1. Run app in local mode (no Supabase configured) — admin dashboard will use the in-memory repository.
2. Open the app, sign in as a local user, open Admin via Settings (if admin nav shows).
3. Use the search, filters, and toggle switches to validate behavior.

Next steps
- Implement pagination and bulk actions in UI and backend.
- Add tests: unit tests for `MemoryAdminRepository`, widget tests for `AdminDashboardScreen` interactions.
- If you want, I can implement one of these next (pick one).
