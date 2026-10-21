-- Run this in Supabase SQL Editor to prevent duplicate profile animals.

-- Preserve the first existing choice, then give later duplicates an unused
-- animal so the unique index can be added without losing any members.
with duplicate_members as (
  select group_id, user_id, joined_at,
         row_number() over (partition by group_id, avatar order by joined_at, user_id) as duplicate_position
  from public.memberships
), replacements as (
  select group_id, user_id,
         row_number() over (partition by group_id order by joined_at, user_id) as replacement_position
  from duplicate_members
  where duplicate_position > 1
), available_avatars as (
  select g.id as group_id, choice as avatar,
         row_number() over (partition by g.id order by position) as replacement_position
  from public.groups g
  cross join unnest(array['cow','koala','ram','flamingo','panda','llama','elephant','crocodile','gorilla','moose','chameleon','bear','giraffe','tiger','zebra','lion']::text[]) with ordinality as choices(choice, position)
  where not exists (select 1 from public.memberships m where m.group_id = g.id and m.avatar = choice)
)
update public.memberships m
set avatar = available_avatars.avatar
from replacements
join available_avatars using (group_id, replacement_position)
where m.group_id = replacements.group_id and m.user_id = replacements.user_id;

create unique index if not exists memberships_avatar_uq
  on public.memberships (group_id, avatar);

create or replace function public.join_group(p_code text, p_name text, p_colour text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  g public.groups;
  v_name text := public._clean(p_name);
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_avatar text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into g from public.groups where code = upper(btrim(p_code));
  if not found then raise exception 'No race with that code'; end if;
  if exists (select 1 from public.memberships where group_id = g.id and user_id = auth.uid()) then return g.id; end if;
  if g.locked then raise exception 'This race is locked. Ask the host to unlock it'; end if;
  if v_name is null then raise exception 'Pick a name'; end if;
  if char_length(v_name) > 20 then raise exception 'Names are 20 characters or fewer'; end if;

  perform 1 from public.groups where id = g.id for update;
  select choice into v_avatar
  from unnest(array['cow','koala','ram','flamingo','panda','llama','elephant','crocodile','gorilla','moose','chameleon','bear','giraffe','tiger','zebra','lion']::text[]) with ordinality as choices(choice, position)
  where not exists (select 1 from public.memberships where group_id = g.id and avatar = choice)
  order by position limit 1;
  if v_avatar is null then raise exception 'This race has no profile pictures left'; end if;

  begin
    insert into public.memberships (group_id, user_id, display_name, colour, avatar)
    values (g.id, auth.uid(), v_name, p_colour, v_avatar);
  exception when unique_violation then raise exception 'That name is taken in this race';
  end;
  if g.owner_id is null and g.owner_email is not null and lower(g.owner_email) = v_email then
    update public.groups set owner_id = auth.uid() where id = g.id;
  end if;
  return g.id;
end $$;

drop function if exists public.update_profile(uuid, text, text);
create or replace function public.update_profile(p_group uuid, p_name text, p_colour text, p_avatar text default 'cow')
returns void language plpgsql security definer set search_path = public as $$
declare v_name text := public._clean(p_name);
begin
  if not public.is_member(p_group) then raise exception 'You are not in this race'; end if;
  if v_name is null then raise exception 'Pick a name'; end if;
  if char_length(v_name) > 20 then raise exception 'Names are 20 characters or fewer'; end if;
  if coalesce(p_colour, '') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Pick a profile colour'; end if;
  if coalesce(p_avatar, '') not in ('cow','koala','ram','flamingo','panda','llama','elephant','crocodile','gorilla','moose','chameleon','bear','giraffe','tiger','zebra','lion') then raise exception 'Pick a profile picture'; end if;
  perform 1 from public.groups where id = p_group for update;
  if exists (select 1 from public.memberships where group_id = p_group and avatar = p_avatar and user_id <> auth.uid()) then
    raise exception 'That profile picture is already taken in this race';
  end if;
  begin
    update public.memberships set display_name = v_name, colour = p_colour, avatar = p_avatar
     where group_id = p_group and user_id = auth.uid();
  exception when unique_violation then raise exception 'That name is taken in this race';
  end;
end $$;
