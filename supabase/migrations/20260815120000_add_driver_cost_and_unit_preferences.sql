-- The cost model, the shape of the driver's week and their display units were
-- all modelled in the app and validated on the way in and out of local storage,
-- but `driver_preferences` only ever carried the name, the daily goal, the
-- vehicle rate and the theme. Everything else was therefore device-local: a
-- driver who set their MPG on one phone and signed in on another was quietly
-- handed the shipped defaults back.
--
-- All nullable or defaulted, so a client on an older build that upserts without
-- these columns keeps working and simply leaves them alone.
alter table public.driver_preferences
  -- 'gasoline' | 'electric'. Text rather than an enum so adding a third energy
  -- source later does not need a migration on a type other tables reference.
  add column if not exists energy_source text not null default 'gasoline',

  -- Miles per US gallon, or miles per kWh when the car is electric. Stored in
  -- one unit regardless of what the driver is shown: a stored figure that
  -- changes meaning when a display preference changes is a corruption waiting
  -- to happen.
  add column if not exists fuel_efficiency numeric(10, 4) not null default 25,

  -- Price per US gallon, or per kWh.
  add column if not exists fuel_price numeric(10, 4) not null default 3.5,

  -- The lowest hourly profit the driver considers worth the trip. Zero is
  -- meaningful — it means "judge me against my own average" — so this is not
  -- nullable.
  add column if not exists hourly_floor numeric(10, 2) not null default 25,

  -- ISO-8601 weekday numbering, matching Dart's DateTime: 1 = Monday,
  -- 7 = Sunday. Only those two are offered, because a pay week starting on a
  -- Wednesday is not a thing any platform does.
  add column if not exists week_starts_on smallint not null default 1,

  add column if not exists driving_days_per_week smallint not null default 5,

  -- Display only, but synced: a driver who chose kilometres on their phone
  -- should not be shown miles on a new one.
  add column if not exists distance_unit text not null default 'miles',
  add column if not exists currency_code text not null default 'USD';

-- Constraints rather than trust. These arrive from a client, and a value the
-- app cannot represent would come back as a default on the next restore
-- anyway — failing the write is the honest version of that.
alter table public.driver_preferences
  drop constraint if exists driver_preferences_energy_source_check;
alter table public.driver_preferences
  add constraint driver_preferences_energy_source_check
  check (energy_source in ('gasoline', 'electric'));

alter table public.driver_preferences
  drop constraint if exists driver_preferences_week_starts_on_check;
alter table public.driver_preferences
  add constraint driver_preferences_week_starts_on_check
  check (week_starts_on in (1, 7));

alter table public.driver_preferences
  drop constraint if exists driver_preferences_driving_days_check;
alter table public.driver_preferences
  add constraint driver_preferences_driving_days_check
  check (driving_days_per_week between 1 and 7);

alter table public.driver_preferences
  drop constraint if exists driver_preferences_distance_unit_check;
alter table public.driver_preferences
  add constraint driver_preferences_distance_unit_check
  check (distance_unit in ('miles', 'kilometres'));

-- Ranges match the client's own validation, so the two cannot drift into a
-- state where the app offers a figure the database rejects.
alter table public.driver_preferences
  drop constraint if exists driver_preferences_cost_ranges_check;
alter table public.driver_preferences
  add constraint driver_preferences_cost_ranges_check
  check (
    fuel_efficiency > 0
    and fuel_efficiency <= 500
    and fuel_price >= 0
    and fuel_price <= 100
    and hourly_floor >= 0
    and hourly_floor <= 10000
  );
