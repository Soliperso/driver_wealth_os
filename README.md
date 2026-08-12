# Driver Wealth OS

A polished Flutter MVP that helps rideshare drivers understand true profit without arranging rides, matching passengers, setting fares, or processing transportation payments.

## Current slices

- Onboarding → Add completed shift → Profit calculation → Shift result → Today dashboard
- Editable daily profit goal
- Persistent shift history with detail, edit, and delete
- Weekly performance and relative Earnings DNA grades
- One persistent Freedom goal tied to positive true profit
- Money Leak detection that never counts one shift twice
- A deterministic, data-backed Profit Coach
- Connect work accounts → secure Argyle Link session → normalized earnings sync scaffolding

The calculation includes direct expenses plus a configurable vehicle cost per mile, then reports net profit, net per hour, net per mile, and keep rate.

## Architecture

- Feature-first Flutter folders
- Vertical slices with domain logic outside widgets
- Responsive Material 3 interface
- Bottom navigation below 800 px and navigation rail on larger screens
- Light and dark themes
- Hosted Supabase schema with row-level security
- Supabase Edge Functions for connection sessions, earnings sync, and signed webhooks
- Argyle Link Flutter SDK with secrets kept on the backend

## Run

```sh
flutter pub get
flutter run
```

Without backend configuration and provider credentials, the app remains fully usable for manual tracking and shows an honest setup message when account connection is selected.

## Hosted backend — no Docker

Create or select a dedicated Supabase project, then run:

```sh
supabase link --project-ref YOUR_PROJECT_REF
supabase config push
supabase db push
supabase secrets set ARGYLE_API_KEY_ID=YOUR_KEY_ID ARGYLE_API_KEY_SECRET=YOUR_KEY_SECRET ARGYLE_ENV=sandbox ARGYLE_WEBHOOK_SECRET=YOUR_RANDOM_SECRET
supabase functions deploy create-connection-session
supabase functions deploy sync-earnings
supabase functions deploy argyle-webhook --no-verify-jwt
```

Run Flutter with the hosted public values:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY \
  --dart-define=INCOME_SYNC_ENABLED=true
```

Never place the Argyle API secret or Supabase service-role key in Flutter or commit them to the repository.

## Verify

```sh
flutter analyze
flutter test
```

See [`docs/MVP_STATUS.md`](docs/MVP_STATUS.md) for the PRD/roadmap audit, completed scope, and credential-dependent activation work.
