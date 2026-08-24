# Driver Wealth OS MVP Status

This audit uses the accepted vertical-slice roadmap from the project conversation because the original generated PRD and roadmap Markdown downloads were not present in the local project.

## Product boundary

The app remains driver-facing financial software. It does not match riders, dispatch drivers, set passenger fares, collect transportation payments, or provide transportation. This keeps the implementation aligned with the PRD's core product boundary.

## Roadmap audit

| Slice | Outcome | Status | Evidence |
|---|---|---:|---|
| 0 — Start/Stop Driving | Tap Start → time and mileage tracked automatically → End Shift → enter earnings → profit | Complete | `features/driving`; session, accumulator and flow tests |
| 1 — One Shift, One Truth | Onboarding → completed shift → profit calculation → result → dashboard | Complete | `onboarding`, `shifts`, and `today` features; calculation unit tests |
| 2 — History | Persistent shifts, detail, edit, delete | Complete | `history` feature and app-store persistence tests |
| 3 — Weekly Performance | Weekly totals, net/hour, keep rate, comparison, best shift | Complete | `ShiftAnalytics.weekly` and History weekly card |
| 4 — Earnings DNA v1 | Day/time patterns with relative A–D profitability grades | Complete | `ShiftAnalytics.earningsPatterns` and Earnings DNA card |
| 5 — Freedom Goal | One editable goal connected to true profit | Removed | Cut after the Coach redesign: the goal ring restated the daily goal already on Today, and its projection was the only place the app forecast earnings. `freedom_goals` dropped in `20260820130000_remove_retired_goal_data.sql`. |
| 6 — Money Leaks v1 | Detect negative profit, weak hourly performance, and low keep rate | Complete | One highest-value leak per shift, preventing duplicate recovery totals |
| 7 — Backend | Hosted auth/data/sync foundation | Foundation complete; activation external | Supabase migrations and Edge Functions exist. Live account import requires provider credentials and enabled runtime configuration. |
| 8 — Coach | One prioritized recommendation backed by calculated data | Complete for MVP | Deterministic local Profit Coach using goals, weekly performance, patterns, and leaks. No fabricated AI responses. |

## How a shift is captured

The core loop is now Start Driving → work → End Shift → enter earnings. Time and mileage are
measured by the phone; only the money is supplied by the driver.

- **Time** comes from stored start and end timestamps, never a running counter, so the figure
  survives the OS suspending or killing the app mid-shift.
- **Mileage** is accumulated from GPS fixes, leg by leg — not from a routing service. Drivers
  circle airports, reposition and deadhead, so miles actually driven and the optimal road distance
  between two points are different numbers, and only the former justifies a cost-per-mile
  deduction. The accumulator rejects inaccurate fixes, implausible jumps, and stationary drift, and
  requires speed evidence before crediting a short leg.
- **Earnings** arrive through `EarningsSource`. Manual entry is the only implementation that ships.
  Provider APIs — Uber's Driver API among them — require an application and approval, so the
  product deliberately does not depend on one; an approved integration slots in behind the same
  interface without touching the profit engine.

Manual shift entry remains available as a first-class fallback for drivers who would rather not be
tracked, or who are logging a shift they already finished.

## Calculation methodology

For each completed shift:

```text
vehicle wear = miles × non-fuel vehicle wear rate
total costs = fuel/tolls/parking + vehicle wear
true profit = gross earnings − total costs
net per hour = true profit ÷ hours
net per mile = true profit ÷ miles
keep rate = true profit ÷ gross earnings
```

Money values are rounded to cents at calculation boundaries. Summaries and analytics deduplicate records by shift ID. Money Leak recovery totals select at most one leak per shift so overlapping rules do not double-count the same earnings gap.

## Remaining external activation

Live work-account import cannot be truthfully completed or verified without the selected provider's API credentials. When credentials are available, the remaining activation steps are:

1. Add provider secrets to the hosted Supabase project.
2. Enable income sync in Flutter runtime configuration.
3. Complete a sandbox account connection.
4. Verify webhook signature handling, normalized import, and idempotent upsert against the hosted database.

This dependency does not block the local MVP, manual tracking, analytics, or Profit Coach.

## Verification

Run:

```sh
flutter analyze
flutter test
```

The automated suite covers calculation accuracy, rounding, duplicate prevention, persistence, daily-goal states, platform coverage, history operations, weekly analytics, Earnings DNA, Money Leaks, and Coach behavior.
