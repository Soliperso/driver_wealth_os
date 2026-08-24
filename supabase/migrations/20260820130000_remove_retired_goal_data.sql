-- The retired savings-goal experience is no longer part of the product.
-- Dropping the table removes its stored records, policies, and triggers.
drop table if exists public.freedom_goals cascade;
