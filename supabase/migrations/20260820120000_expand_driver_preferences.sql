-- Settings that already exist in the local snapshot also need to survive a
-- reinstall or a second device. Defaults match AppSnapshot so deploying this
-- migration does not change any existing driver's calculations.
alter table public.driver_preferences
  add column if not exists energy_source text not null default 'gasoline',
  add column if not exists fuel_efficiency numeric(10, 2) not null default 25,
  add column if not exists fuel_price numeric(10, 3) not null default 3.50,
  add column if not exists hourly_floor numeric(10, 2) not null default 25,
  add column if not exists week_starts_on smallint not null default 1,
  add column if not exists driving_days_per_week smallint not null default 5,
  add column if not exists distance_unit text not null default 'miles';

alter table public.driver_preferences
  drop constraint if exists driver_preferences_energy_source_check,
  add constraint driver_preferences_energy_source_check
    check (energy_source in ('gasoline', 'hybrid', 'electric')),
  drop constraint if exists driver_preferences_fuel_efficiency_check,
  add constraint driver_preferences_fuel_efficiency_check
    check (fuel_efficiency > 0 and fuel_efficiency <= 500),
  drop constraint if exists driver_preferences_fuel_price_check,
  add constraint driver_preferences_fuel_price_check
    check (fuel_price >= 0 and fuel_price <= 100),
  drop constraint if exists driver_preferences_hourly_floor_check,
  add constraint driver_preferences_hourly_floor_check
    check (hourly_floor > 0 and hourly_floor <= 10000),
  drop constraint if exists driver_preferences_week_starts_on_check,
  add constraint driver_preferences_week_starts_on_check
    check (week_starts_on in (1, 7)),
  drop constraint if exists driver_preferences_driving_days_check,
  add constraint driver_preferences_driving_days_check
    check (driving_days_per_week between 1 and 7),
  drop constraint if exists driver_preferences_distance_unit_check,
  add constraint driver_preferences_distance_unit_check
    check (distance_unit in ('miles', 'kilometers'));
