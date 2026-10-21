-- Run this once in the Supabase SQL Editor for an existing race.
-- Memberships and applications are linked by group ID, so changing the code
-- keeps all existing race data intact.
update public.groups
set code = 'SUEDE26'
where code = 'RACE24';
