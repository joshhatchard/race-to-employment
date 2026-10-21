-- =====================================================================
-- Breads Up!: database schema
-- Paste this whole file into Supabase > SQL Editor > New query > Run.
-- BEFORE running: scroll to the bottom and put YOUR Google email in the
-- seed row, so you become the race owner when you join.
-- =====================================================================

-- ---------- helpers ---------------------------------------------------

create or replace function public.sydney_today()
returns date language sql stable as $$
  select (now() at time zone 'Australia/Sydney')::date
$$;

create or replace function public._clean(p text)
returns text language sql immutable as $$
  select nullif(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')), '')
$$;

-- ---------- tables ----------------------------------------------------

create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name        text not null,
  start_at    timestamptz not null,
  closed      boolean not null default false,
  locked      boolean not null default false,
  owner_id    uuid references auth.users(id) on delete set null,
  owner_email text,
  created_at  timestamptz not null default now()
);

create table if not exists public.memberships (
  group_id          uuid not null references public.groups(id) on delete cascade,
  user_id           uuid not null references auth.users(id) on delete cascade,
  display_name      text not null check (char_length(display_name) between 1 and 20),
  colour            text not null check (colour ~ '^#[0-9a-fA-F]{6}$'),
  avatar            text not null default 'cow',
  ready             boolean not null default false,
  status            text not null default 'searching' check (status in ('searching', 'employed')),
  hired_at          timestamptz,
  hired_rank        int,
  hired_company     text,
  hide_hire_company boolean not null default false,
  joined_at         timestamptz not null default now(),
  primary key (group_id, user_id)
);
create unique index if not exists memberships_name_uq
  on public.memberships (group_id, lower(display_name));

alter table public.memberships add column if not exists avatar text not null default 'cow';

create table if not exists public.applications (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  company_name text not null check (char_length(company_name) between 1 and 80),
  company_key  text not null,
  role         text check (role is null or char_length(role) <= 80),
  url          text check (url is null or char_length(url) <= 300),
  note         text check (note is null or char_length(note) <= 300),
  source       text not null default 'applied' check (source in ('applied', 'inbound')),
  status       text not null default 'applied'
               check (status in ('applied', 'interviewing', 'offer', 'accepted', 'rejected')),
  applied_on   date not null default public.sydney_today(),
  batch_id     uuid,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index if not exists applications_group_idx on public.applications (group_id, user_id, applied_on);
create index if not exists applications_batch_idx on public.applications (batch_id);
create index if not exists applications_group_created_idx on public.applications (group_id, created_at desc);

create table if not exists public.events (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references public.groups(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  application_id uuid not null references public.applications(id) on delete cascade,
  type           text not null check (type in ('interview', 'offer', 'offer_accepted', 'rejection')),
  stage          text check (stage is null or char_length(stage) <= 30),
  occurred_on    date not null default public.sydney_today(),
  created_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index if not exists events_group_idx on public.events (group_id, user_id);
create index if not exists events_app_idx on public.events (application_id);
create index if not exists events_group_created_idx on public.events (group_id, created_at desc);

-- ---------- read access (row level security) ---------------------------
-- Clients can only READ their own group's rows. Every write goes through
-- the functions below, which enforce the rules.

create or replace function public.is_member(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.memberships
    where group_id = p_group and user_id = auth.uid()
  )
$$;

alter table public.groups       enable row level security;
alter table public.memberships  enable row level security;
alter table public.applications enable row level security;
alter table public.events       enable row level security;

drop policy if exists groups_read       on public.groups;
drop policy if exists memberships_read  on public.memberships;
drop policy if exists applications_read on public.applications;
drop policy if exists events_read       on public.events;

create policy groups_read       on public.groups       for select to authenticated using (public.is_member(id));
create policy memberships_read  on public.memberships  for select to authenticated using (public.is_member(group_id));
create policy applications_read on public.applications for select to authenticated using (public.is_member(group_id));
create policy events_read       on public.events       for select to authenticated using (public.is_member(group_id));

-- ---------- internal helpers ------------------------------------------

-- Every logging action calls this first: signed in, in the race, race has
-- started, race not closed, and you have not already been hired.
create or replace function public._require_live(p_group uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  g public.groups;
  m public.memberships;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into g from public.groups where id = p_group;
  if not found then raise exception 'Race not found'; end if;
  select * into m from public.memberships where group_id = p_group and user_id = auth.uid();
  if not found then raise exception 'You are not in this race'; end if;
  if now() < g.start_at then raise exception 'The race has not started yet'; end if;
  if g.closed then raise exception 'This race is closed'; end if;
  if m.status = 'employed' then raise exception 'You are already hired, so your race is over'; end if;
end $$;

-- Application status is always derived from its latest live event.
create or replace function public._recompute_status(p_app uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  t text;
  s text;
begin
  select type into t from public.events
   where application_id = p_app and deleted_at is null
   order by created_at desc, id desc limit 1;
  s := case t
         when 'interview' then 'interviewing'
         when 'offer' then 'offer'
         when 'offer_accepted' then 'accepted'
         when 'rejection' then 'rejected'
         else 'applied'
       end;
  update public.applications set status = s where id = p_app;
  -- an inbound entry with no events left has nothing to show
  if t is null then
    update public.applications
       set deleted_at = coalesce(deleted_at, now())
     where id = p_app and source = 'inbound';
  end if;
end $$;

create or replace function public._revert_hire(p_group uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    update public.events set deleted_at = now()
     where group_id = p_group and user_id = p_user
       and type = 'offer_accepted' and deleted_at is null
    returning application_id
  loop
    perform public._recompute_status(r.application_id);
  end loop;

  update public.memberships
     set status = 'searching', hired_at = null, hired_rank = null,
         hired_company = null, hide_hire_company = false
   where group_id = p_group and user_id = p_user;

  update public.memberships m
     set hired_rank = x.rn
    from (
      select user_id, row_number() over (order by hired_at) as rn
        from public.memberships
       where group_id = p_group and status = 'employed'
    ) x
   where m.group_id = p_group and m.user_id = x.user_id;
end $$;

-- ---------- public functions (called from the app) ----------------------

create or replace function public.get_server_time()
returns timestamptz language sql stable as $$ select now() $$;

-- Join a race with its code. Safe to call again: returns the race you are in.
create or replace function public.join_group(p_code text, p_name text, p_colour text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  g public.groups;
  v_name text := public._clean(p_name);
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into g from public.groups where code = upper(btrim(p_code));
  if not found then raise exception 'No race with that code'; end if;

  if exists (select 1 from public.memberships where group_id = g.id and user_id = auth.uid()) then
    return g.id;
  end if;

  if g.locked then raise exception 'This race is locked. Ask the host to unlock it'; end if;
  if v_name is null then raise exception 'Pick a name'; end if;
  if char_length(v_name) > 20 then raise exception 'Names are 20 characters or fewer'; end if;

  begin
    insert into public.memberships (group_id, user_id, display_name, colour)
    values (g.id, auth.uid(), v_name, p_colour);
  exception when unique_violation then
    raise exception 'That name is taken in this race';
  end;

  if g.owner_id is null and g.owner_email is not null and lower(g.owner_email) = v_email then
    update public.groups set owner_id = auth.uid() where id = g.id;
  end if;
  return g.id;
end $$;

create or replace function public.set_ready(p_group uuid, p_ready boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_group) then raise exception 'You are not in this race'; end if;
  update public.memberships set ready = coalesce(p_ready, false)
   where group_id = p_group and user_id = auth.uid();
end $$;

-- Leave a race before it starts. A participant may only remove their own membership.
create or replace function public.leave_group(p_group uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_group) then raise exception 'You are not in this race'; end if;
  delete from public.memberships where group_id = p_group and user_id = auth.uid();
end $$;

-- Replace the legacy three-argument RPC. Keeping both overloads makes the
-- PostgREST RPC resolver reject profile saves as ambiguous.
drop function if exists public.update_profile(uuid, text, text);

-- Update the small profile shown in the lobby. Names remain unique per race.
create or replace function public.update_profile(p_group uuid, p_name text, p_colour text, p_avatar text default 'cow')
returns void language plpgsql security definer set search_path = public as $$
declare v_name text := public._clean(p_name);
begin
  if not public.is_member(p_group) then raise exception 'You are not in this race'; end if;
  if v_name is null then raise exception 'Pick a name'; end if;
  if char_length(v_name) > 20 then raise exception 'Names are 20 characters or fewer'; end if;
  if coalesce(p_colour, '') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Pick a profile colour'; end if;
  if coalesce(p_avatar, '') not in ('cow','koala','ram','flamingo','panda','llama','elephant','crocodile','gorilla','moose','chameleon','bear','giraffe','tiger','zebra','lion') then raise exception 'Pick a profile picture'; end if;
  begin
    update public.memberships set display_name = v_name, colour = p_colour, avatar = p_avatar
     where group_id = p_group and user_id = auth.uid();
  exception when unique_violation then
    raise exception 'That name is taken in this race';
  end;
end $$;

-- Log one or more applications. Each item is {"company": "..."}.
-- Always stamped with today's Sydney date: no backdating.
-- Returns {status:'duplicates', duplicates:[...]} if you applied to any of
-- them in the last 14 days (nothing is saved), or {status:'ok', ...}.
create or replace function public.log_applications(p_group uuid, p_items jsonb, p_allow_dupes boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb;
  v_name text;
  v_key text;
  v_batch uuid := gen_random_uuid();
  v_dupes text[] := '{}';
  v_seen text[] := '{}';
  v_n int := 0;
  v_first uuid;
  v_id uuid;
begin
  perform public._require_live(p_group);
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one company';
  end if;
  if jsonb_array_length(p_items) > 10 then raise exception 'Log up to 10 at a time'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_name := left(public._clean(v_item ->> 'company'), 80);
    continue when v_name is null;
    v_key := lower(v_name);
    continue when v_key = any(v_seen);
    v_seen := v_seen || v_key;
    if not coalesce(p_allow_dupes, false) and exists (
      select 1 from public.applications
       where group_id = p_group and user_id = auth.uid()
         and company_key = v_key and source = 'applied' and deleted_at is null
         and applied_on >= public.sydney_today() - 14
    ) then
      v_dupes := v_dupes || v_name;
    end if;
  end loop;

  if coalesce(array_length(v_dupes, 1), 0) > 0 then
    return jsonb_build_object('status', 'duplicates', 'duplicates', to_jsonb(v_dupes));
  end if;

  v_seen := '{}';
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_name := left(public._clean(v_item ->> 'company'), 80);
    continue when v_name is null;
    v_key := lower(v_name);
    continue when v_key = any(v_seen);
    v_seen := v_seen || v_key;
    insert into public.applications (group_id, user_id, company_name, company_key, source, batch_id)
    values (p_group, auth.uid(), v_name, v_key, 'applied', v_batch)
    returning id into v_id;
    v_first := coalesce(v_first, v_id);
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then raise exception 'Add at least one company'; end if;
  return jsonb_build_object('status', 'ok', 'batch_id', v_batch, 'count', v_n, 'first_id', v_first);
end $$;

create or replace function public.undo_batch(p_batch uuid)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.applications set deleted_at = now()
   where batch_id = p_batch and user_id = auth.uid()
     and deleted_at is null and status = 'applied';
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.update_application(p_id uuid, p_role text, p_url text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.applications
     set role = left(public._clean(p_role), 80),
         url  = left(public._clean(p_url), 300),
         note = left(public._clean(p_note), 300)
   where id = p_id and user_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'Application not found'; end if;
end $$;

create or replace function public.remove_application(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a public.applications;
begin
  select * into a from public.applications where id = p_id and user_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'Application not found'; end if;
  if a.status = 'accepted' then raise exception 'Undo your hire first'; end if;
  update public.events set deleted_at = now() where application_id = p_id and deleted_at is null;
  update public.applications set deleted_at = now() where id = p_id;
end $$;

-- Log an interview, offer or rejection against one of your applications.
-- An interview can instead name a company you never applied to (inbound).
create or replace function public.log_event(
  p_group uuid, p_type text, p_application uuid default null,
  p_company text default null, p_stage text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.applications;
  v_company text := left(public._clean(p_company), 80);
  v_event uuid;
begin
  perform public._require_live(p_group);
  if p_type not in ('interview', 'offer', 'rejection') then raise exception 'Unknown event type'; end if;

  if p_application is not null then
    select * into a from public.applications
     where id = p_application and user_id = auth.uid() and group_id = p_group and deleted_at is null;
    if not found then raise exception 'Application not found'; end if;
  elsif p_type = 'interview' and v_company is not null then
    select * into a from public.applications
     where group_id = p_group and user_id = auth.uid() and company_key = lower(v_company)
       and deleted_at is null and status in ('applied', 'interviewing')
     order by created_at desc limit 1;
    if not found then
      insert into public.applications (group_id, user_id, company_name, company_key, source)
      values (p_group, auth.uid(), v_company, lower(v_company), 'inbound')
      returning * into a;
    end if;
  else
    raise exception 'Pick a company';
  end if;

  if p_type = 'interview' and a.status not in ('applied', 'interviewing') then
    raise exception 'That application is already % ', a.status;
  elsif p_type = 'offer' and a.status not in ('applied', 'interviewing') then
    raise exception 'That application is already %', a.status;
  elsif p_type = 'rejection' and a.status not in ('applied', 'interviewing', 'offer') then
    raise exception 'That application is already %', a.status;
  end if;

  insert into public.events (group_id, user_id, application_id, type, stage)
  values (p_group, auth.uid(), a.id, p_type, left(public._clean(p_stage), 30))
  returning id into v_event;

  perform public._recompute_status(a.id);
  return jsonb_build_object('application_id', a.id, 'event_id', v_event);
end $$;

create or replace function public.remove_event(p_event uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  select * into e from public.events where id = p_event and user_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'Event not found'; end if;
  if e.type = 'offer_accepted' then raise exception 'Use undo on your hire instead'; end if;
  update public.events set deleted_at = now() where id = p_event;
  perform public._recompute_status(e.application_id);
end $$;

-- The one big tap. The group row is locked first so two people tapping at
-- the same moment can never share a rank.
create or replace function public.accept_offer(p_group uuid, p_application uuid, p_hide boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.applications;
  v_rank int;
begin
  perform 1 from public.groups where id = p_group for update;
  perform public._require_live(p_group);

  select * into a from public.applications
   where id = p_application and user_id = auth.uid() and group_id = p_group and deleted_at is null;
  if not found then raise exception 'Application not found'; end if;
  if a.status <> 'offer' then raise exception 'Log the offer first'; end if;

  select count(*) + 1 into v_rank from public.memberships
   where group_id = p_group and status = 'employed';

  update public.memberships
     set status = 'employed', hired_at = now(), hired_rank = v_rank,
         hired_company = a.company_name, hide_hire_company = coalesce(p_hide, false)
   where group_id = p_group and user_id = auth.uid();

  insert into public.events (group_id, user_id, application_id, type)
  values (p_group, auth.uid(), a.id, 'offer_accepted');

  update public.applications set status = 'accepted' where id = a.id;
  return jsonb_build_object('rank', v_rank);
end $$;

-- Take back a hire within 10 minutes.
create or replace function public.undo_accept(p_group uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.memberships;
begin
  perform 1 from public.groups where id = p_group for update;
  select * into m from public.memberships where group_id = p_group and user_id = auth.uid();
  if not found or m.status <> 'employed' then raise exception 'You are not marked as hired'; end if;
  if m.hired_at < now() - interval '10 minutes' then
    raise exception 'The 10 minute undo window has passed. Ask the host to revert it';
  end if;
  perform public._revert_hire(p_group, auth.uid());
end $$;

-- Owner tools
create or replace function public.owner_revert_hire(p_group uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from public.groups where id = p_group for update;
  if not exists (select 1 from public.groups where id = p_group and owner_id = auth.uid()) then
    raise exception 'Only the host can do that';
  end if;
  perform public._revert_hire(p_group, p_user);
end $$;

create or replace function public.set_group_state(p_group uuid, p_closed boolean, p_locked boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.groups
     set closed = coalesce(p_closed, closed), locked = coalesce(p_locked, locked)
   where id = p_group and owner_id = auth.uid();
  if not found then raise exception 'Only the host can do that'; end if;
end $$;

-- For later: let anyone start their own race. Returns the join code.
create or replace function public.create_group(p_name text, p_start timestamptz)
returns text language plpgsql security definer set search_path = public as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_name text := left(public._clean(p_name), 40);
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if v_name is null then raise exception 'Name your race'; end if;
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.groups where code = v_code);
  end loop;
  insert into public.groups (code, name, start_at, owner_id)
  values (v_code, v_name, coalesce(p_start, now()), auth.uid());
  return v_code;
end $$;

-- ---------- standings and feed ------------------------------------------

drop function if exists public.race_standings(uuid);
create function public.race_standings(p_group uuid)
returns table (
  user_id uuid, display_name text, colour text, avatar text, ready boolean, status text,
  hired_at timestamptz, hired_rank int, hired_company text,
  applications int, interviews int, offers int, rejections int,
  current_streak int, longest_streak int, last_applied_on date)
language sql stable security definer set search_path = public as $$
  with m as (
    select mm.*,
           case when mm.status = 'employed'
                then (mm.hired_at at time zone 'Australia/Sydney')::date
                else public.sydney_today() end as ref
      from public.memberships mm
     where mm.group_id = p_group and public.is_member(p_group)
  ),
  a as (
    select ap.user_id, ap.applied_on
      from public.applications ap
     where ap.group_id = p_group and ap.source = 'applied' and ap.deleted_at is null
  ),
  days as (select distinct user_id, applied_on as d from a),
  isl as (
    select user_id, min(d) as s, max(d) as e, count(*)::int as len
      from (select user_id, d,
                   d - (row_number() over (partition by user_id order by d))::int as g
              from days) x
     group by user_id, g
  ),
  ev as (
    select e.user_id,
           count(*) filter (where e.type = 'interview')::int as interviews,
           count(*) filter (where e.type = 'offer')::int as offers,
           count(*) filter (where e.type = 'rejection')::int as rejections
      from public.events e
     where e.group_id = p_group and e.deleted_at is null
     group by e.user_id
  ),
  ac as (
    select user_id, count(*)::int as n, max(applied_on) as last_on from a group by user_id
  )
  select m.user_id, m.display_name, m.colour, m.avatar, m.ready, m.status, m.hired_at, m.hired_rank,
         case when m.hide_hire_company then null else m.hired_company end,
         coalesce(ac.n, 0), coalesce(ev.interviews, 0), coalesce(ev.offers, 0), coalesce(ev.rejections, 0),
         coalesce((select max(i.len) from isl i
                    where i.user_id = m.user_id and i.e >= m.ref - 1 and i.e <= m.ref), 0)::int,
         coalesce((select max(i.len) from isl i where i.user_id = m.user_id), 0)::int,
         ac.last_on
    from m
    left join ac on ac.user_id = m.user_id
    left join ev on ev.user_id = m.user_id
   order by m.joined_at
$$;

create or replace function public.race_feed(p_group uuid, p_limit int default 80)
returns table (
  id uuid, kind text, user_id uuid, display_name text, colour text,
  company text, role text, stage text, batch_id uuid,
  happened_at timestamptz, removed boolean)
language sql stable security definer set search_path = public as $$
  select * from (
    select ap.id, 'application'::text as kind, ap.user_id, m.display_name, m.colour,
           ap.company_name as company, ap.role, null::text as stage, ap.batch_id,
           ap.created_at as happened_at, (ap.deleted_at is not null) as removed
      from public.applications ap
      join public.memberships m on m.group_id = ap.group_id and m.user_id = ap.user_id
     where ap.group_id = p_group and public.is_member(p_group) and ap.source = 'applied'
       and (ap.deleted_at is null or ap.deleted_at - ap.created_at > interval '2 minutes')
    union all
    select e.id, e.type, e.user_id, m.display_name, m.colour,
           case when e.type = 'offer_accepted' and (m.hide_hire_company or e.deleted_at is not null)
                then null else ap.company_name end,
           case when e.type = 'offer_accepted' then null else ap.role end,
           e.stage, null::uuid, e.created_at, (e.deleted_at is not null)
      from public.events e
      join public.applications ap on ap.id = e.application_id
      join public.memberships m on m.group_id = e.group_id and m.user_id = e.user_id
     where e.group_id = p_group and public.is_member(p_group)
       and (e.deleted_at is null or e.deleted_at - e.created_at > interval '2 minutes')
  ) f
  order by f.happened_at desc
  limit least(coalesce(p_limit, 80), 200)
$$;

-- ---------- permissions -------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
grant select on public.groups, public.memberships, public.applications, public.events to authenticated;

revoke all on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
-- internal helpers are only callable from inside the other functions
revoke execute on function public._require_live(uuid) from authenticated;
revoke execute on function public._recompute_status(uuid) from authenticated;
revoke execute on function public._revert_hire(uuid, uuid) from authenticated;

-- ---------- realtime ----------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['applications', 'events', 'memberships', 'groups'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------- the race ----------------------------------------------------
-- Starts Sat 24 Oct 2026, 12:00am Sydney time (UTC+11) = 23 Oct 13:00 UTC.
-- CHANGE THE EMAIL to the Google account you will sign in with. Whoever
-- joins with that email becomes the host (lock joining, close the race,
-- revert a hire).

insert into public.groups (code, name, start_at, owner_email)
values ('SUEDE26', 'Breads Up!', '2026-10-23 13:00:00+00', 'YOUR_EMAIL@gmail.com')
on conflict (code) do nothing;
