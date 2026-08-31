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
| 9 — Taxes & expenses | Costs that are not attached to a shift, categorised for Schedule C, and the vehicle-deduction comparison | Complete | `features/tax`; Taxes tab, expense editor, `TaxYearSummary` and `TaxQuarters`, with expense sync and a combined CSV export. |

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

## The tax year

A gig driver's vehicle deduction is a choice between two methods the IRS treats
as alternatives, not additions: business miles at the published standard rate, or
the real cost of running the car. Most drivers do not know the two are exclusive,
let alone which way round it falls for their vehicle. The app already measures
both inputs, so it makes the comparison and marks the larger one.

- Miles are priced at the rate in force on each shift's own day, so a year the
  IRS changed mid-year accumulates across both bands rather than using a blended
  figure. Driving in a period with no published rate is surfaced as provisional
  rather than silently dropped.
- Expenses carry the Schedule C line they roll up to, and a flag for whether they
  are part of running the car. That flag is what decides the comparison: the
  standard rate already covers fuel, maintenance, insurance and depreciation, so
  a driver claiming it cannot also claim those.
- The estimated-tax figure is framed as "set aside", never as "you owe". The real
  number depends on filing status, other income, a spouse's withholding and the
  QBI deduction, none of which the app asks for. Nothing here is tax advice and
  nothing is filed.
- Receipt images are deliberately not uploaded. A receipt can carry a card
  number, a signature and a home address, and storing every driver's shoebox is
  a liability with no product benefit. An expense can carry a photo taken with
  the camera or picked from the library; the path syncs so a second device knows
  a record has one, and the image stays on the device that took it. Deleting the
  expense deletes the photo, since nothing else holds a copy.

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

The automated suite covers calculation accuracy, rounding, duplicate prevention,
persistence, daily-goal states, platform coverage, history operations, weekly
analytics, Earnings DNA, Money Leaks, Coach behavior, expense sync precedence,
the tax-year comparison, and the CSV export.

It is **fully green** — 275 passing, 3 skipped, 0 failing. The skipped tests are
the visual-golden and tooling suites, which are tagged and run on request:

```sh
flutter test --tags=visual --run-skipped
```

For a long stretch the suite sat at eight failures that were specifications for
features nobody had built yet, which trained everyone to read red as normal. That
is how a navigation tile stayed accidentally commented out for days. A failing
test now means a regression.
