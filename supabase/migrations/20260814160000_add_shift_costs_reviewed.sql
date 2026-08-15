-- Whether the driver has confirmed a shift's fuel, toll and parking costs.
--
-- The column was missing, so the flag never survived a round trip: the client's
-- push had nowhere to write it and its pull had nothing to read, leaving the
-- Shift constructor's default of `true` to apply to every row coming back down.
-- An imported shift still waiting on its costs therefore returned marked
-- reviewed — dropping out of the History review notice and into the platform
-- comparison carrying zero direct expenses, which overstates profit.

-- Added nullable first so the backfill below can tell "never set" apart from
-- "deliberately true". A `not null default true` in one step would make the two
-- indistinguishable and leave the migration unsafe to re-run.
alter table public.shifts
  add column if not exists costs_reviewed boolean;

-- The same rule the client applies when it loads a record written before the
-- flag existed: a hand-entered shift was confirmed by the driver at entry, an
-- imported one never carried cost data at all.
update public.shifts
set costs_reviewed = (source <> 'imported')
where costs_reviewed is null;

alter table public.shifts
  alter column costs_reviewed set default true;

alter table public.shifts
  alter column costs_reviewed set not null;
