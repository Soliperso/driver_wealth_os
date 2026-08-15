-- Per-platform earnings on a shift, so a driver can run Uber and Lyft at once.
--
-- Drivers multi-app. The hours, the miles and therefore the vehicle cost are
-- caused jointly by every app that was live, so a shift per platform would
-- count the same time and mileage twice and halve the apparent cost of
-- driving. A shift keeps one set of resources and gains one earnings line per
-- platform instead — gross being the only figure attributable to a single app.
--
-- A list, not an object keyed by platform id: the order is the order the driver
-- entered them in, and an object would leave that to whatever the JSON decoder
-- does. Shape: [{"platform": "uber", "gross": 142.50}, ...].

alter table public.shifts
  add column if not exists earnings jsonb;

-- Every existing row is single-platform by definition, so its one line is the
-- columns it already has. Written rather than left null so the client's fallback
-- path is only ever exercised by rows in flight from an older build.
update public.shifts
set earnings = jsonb_build_array(
  jsonb_build_object('platform', platform, 'gross', gross)
)
where earnings is null;

alter table public.shifts
  alter column earnings set default '[]'::jsonb;

alter table public.shifts
  alter column earnings set not null;

-- `platform` and `gross` stay, and the client keeps writing both: they are what
-- a device on an older build reads, and a driver who rolls back an update
-- should find their history intact. `gross` remains the shift's whole takings,
-- which is what every existing query and check constraint already assumes.
--
-- The constraint below keeps the two representations agreeing on the total.
-- Without it a bad client could push lines summing to something other than
-- `gross`, and which of the two a given build happened to believe would decide
-- whether the driver's profit came out right.
--
-- Extracted into a function because a check constraint cannot contain a
-- subquery, and summing a jsonb array needs one. Immutable, as a constraint
-- requires: the same array always sums to the same number.
create or replace function public.shift_earnings_total(earnings jsonb)
returns numeric
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(sum((line ->> 'gross')::numeric), 0)
  from jsonb_array_elements(coalesce(earnings, '[]'::jsonb)) as line;
$$;

alter table public.shifts
  drop constraint if exists shifts_earnings_match_gross;

-- Tolerance rather than equality: each side is rounded to cents on its own, so
-- a shift split across several apps can land a cent away from its own total.
alter table public.shifts
  add constraint shifts_earnings_match_gross check (
    jsonb_typeof(earnings) = 'array'
    and (
      -- A tombstone carries no figures worth checking. The delete path writes
      -- only the key columns, and this row is about to stop existing anyway.
      deleted_at is not null
      or abs(public.shift_earnings_total(earnings) - gross) <= 0.01
    )
  );
