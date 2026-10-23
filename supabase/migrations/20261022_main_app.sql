-- Breads Up! active-race MVP. Run once in Supabase SQL Editor.
-- This only adds tables/functions; it does not delete or reset existing data.

create table if not exists public.interviews (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  company_name text not null check (char_length(company_name) between 1 and 80),
  round_number int not null check (round_number >= 1 and round_number <= 99),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists interviews_group_user_created_idx on public.interviews (group_id, user_id, created_at desc);

create table if not exists public.activity_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in ('application', 'interview', 'overtake', 'employment')),
  source_id uuid,
  company_name text check (company_name is null or char_length(company_name) <= 80),
  interview_round int check (interview_round is null or interview_round >= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists activity_events_group_created_idx on public.activity_events (group_id, created_at desc);
create index if not exists activity_events_source_idx on public.activity_events (source_id);

create table if not exists public.activity_reactions (
  event_id uuid not null references public.activity_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('🔥', '💀', '🍞', '👀', '🫡', '🎉')),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id, emoji)
);

alter table public.interviews enable row level security;
alter table public.activity_events enable row level security;
alter table public.activity_reactions enable row level security;

drop policy if exists interviews_read on public.interviews;
drop policy if exists activity_events_read on public.activity_events;
drop policy if exists activity_reactions_read on public.activity_reactions;
create policy interviews_read on public.interviews for select to authenticated using (public.is_member(group_id));
create policy activity_events_read on public.activity_events for select to authenticated using (public.is_member(group_id));
create policy activity_reactions_read on public.activity_reactions for select to authenticated using (
  exists (select 1 from public.activity_events e where e.id = event_id and public.is_member(e.group_id))
);

create or replace function public.race_leaderboard(p_group uuid, p_metric text default 'applications')
returns table (
  user_id uuid, display_name text, colour text, avatar text, status text,
  hired_at timestamptz, hired_rank int, hired_company text,
  applications int, interviews int, "position" int
)
language sql stable security definer set search_path = public as $$
  with counts as (
    select m.user_id, m.display_name, m.colour, m.avatar, m.status, m.hired_at, m.hired_rank,
           case when m.hide_hire_company then null else m.hired_company end as hired_company,
           count(distinct a.id) filter (where a.deleted_at is null and a.source = 'applied')::int as applications,
           count(distinct i.id)::int as interviews
      from public.memberships m
      left join public.applications a on a.group_id = m.group_id and a.user_id = m.user_id
      left join public.interviews i on i.group_id = m.group_id and i.user_id = m.user_id
     where m.group_id = p_group and public.is_member(p_group)
     group by m.group_id, m.user_id
  )
  select *, rank() over (order by case when p_metric = 'interviews' then interviews else applications end desc,
                                 display_name asc, user_id asc)::int as "position"
    from counts
   order by case when p_metric = 'interviews' then interviews else applications end desc,
            display_name asc, user_id asc
$$;

create or replace function public.quick_log_application(p_group uuid, p_company text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_company text := left(public._clean(p_company), 80);
  v_id uuid;
  v_before int;
  v_target record;
begin
  perform public._require_live(p_group);
  if v_company is null then raise exception 'Add a company name'; end if;
  select count(*) into v_before from public.applications
   where group_id = p_group and user_id = auth.uid() and source = 'applied' and deleted_at is null;
  insert into public.applications (group_id, user_id, company_name, company_key, source)
  values (p_group, auth.uid(), v_company, lower(v_company), 'applied') returning id into v_id;
  insert into public.activity_events (group_id, actor_user_id, event_type, source_id, company_name)
  values (p_group, auth.uid(), 'application', v_id, v_company);
  select x.user_id, x.display_name into v_target from public.race_leaderboard(p_group, 'applications') x
   where x.user_id <> auth.uid() and x.applications = v_before and v_before + 1 > x.applications
   order by x.display_name limit 1;
  if found then
    insert into public.activity_events (group_id, actor_user_id, event_type, metadata)
    values (p_group, auth.uid(), 'overtake', jsonb_build_object('target_user_id', v_target.user_id, 'target_name', v_target.display_name));
  end if;
  return v_id;
end $$;

create or replace function public.quick_log_interview(p_group uuid, p_company text, p_round int)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_company text := left(public._clean(p_company), 80);
  v_id uuid;
begin
  perform public._require_live(p_group);
  if v_company is null then raise exception 'Add a company name'; end if;
  if coalesce(p_round, 0) < 1 or p_round > 99 then raise exception 'Choose an interview round'; end if;
  insert into public.interviews (group_id, user_id, company_name, round_number)
  values (p_group, auth.uid(), v_company, p_round) returning id into v_id;
  insert into public.activity_events (group_id, actor_user_id, event_type, source_id, company_name, interview_round)
  values (p_group, auth.uid(), 'interview', v_id, v_company, p_round);
  return v_id;
end $$;

create or replace function public.update_interview(p_id uuid, p_company text, p_round int)
returns void language plpgsql security definer set search_path = public as $$
declare v_company text := left(public._clean(p_company), 80);
begin
  if v_company is null then raise exception 'Add a company name'; end if;
  if coalesce(p_round, 0) < 1 or p_round > 99 then raise exception 'Choose an interview round'; end if;
  update public.interviews set company_name = v_company, round_number = p_round, updated_at = now()
   where id = p_id and user_id = auth.uid();
  if not found then raise exception 'Interview not found'; end if;
  update public.activity_events set company_name = v_company, interview_round = p_round
   where source_id = p_id and event_type = 'interview';
end $$;

create or replace function public.rename_application(p_id uuid, p_company text)
returns void language plpgsql security definer set search_path = public as $$
declare v_company text := left(public._clean(p_company), 80);
begin
  if v_company is null then raise exception 'Add a company name'; end if;
  update public.applications set company_name = v_company, company_key = lower(v_company)
   where id = p_id and user_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'Application not found'; end if;
  update public.activity_events set company_name = v_company
   where source_id = p_id and event_type = 'application';
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
  delete from public.activity_events where source_id = p_id and event_type = 'application';
end $$;

create or replace function public.remove_interview(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.interviews where id = p_id and user_id = auth.uid();
  if not found then raise exception 'Interview not found'; end if;
  delete from public.activity_events where source_id = p_id and event_type = 'interview';
end $$;

create or replace function public.confirm_employment(p_group uuid, p_company text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_company text := left(public._clean(p_company), 80);
  v_rank int;
begin
  perform 1 from public.groups where id = p_group for update;
  if auth.uid() is null or not public.is_member(p_group) then raise exception 'You are not in this race'; end if;
  if v_company is null then raise exception 'Add the company name'; end if;
  if exists (select 1 from public.memberships where group_id = p_group and user_id = auth.uid() and status = 'employed') then
    raise exception 'You are already marked as hired';
  end if;
  select count(*) + 1 into v_rank from public.memberships where group_id = p_group and status = 'employed';
  update public.memberships set status = 'employed', hired_at = now(), hired_rank = v_rank,
    hired_company = v_company, hide_hire_company = false where group_id = p_group and user_id = auth.uid();
  insert into public.activity_events (group_id, actor_user_id, event_type, company_name)
  values (p_group, auth.uid(), 'employment', v_company);
  return jsonb_build_object('rank', v_rank);
end $$;

create or replace function public.correct_employment(p_group uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from public.groups where id = p_group for update;
  if not public.is_member(p_group) then raise exception 'You are not in this race'; end if;
  delete from public.activity_events where group_id = p_group and actor_user_id = auth.uid() and event_type = 'employment';
  update public.memberships set status = 'searching', hired_at = null, hired_rank = null, hired_company = null, hide_hire_company = false
   where group_id = p_group and user_id = auth.uid();
  update public.memberships m set hired_rank = x.rn from (
    select user_id, row_number() over (order by hired_at, user_id) as rn from public.memberships
     where group_id = p_group and status = 'employed'
  ) x where m.group_id = p_group and m.user_id = x.user_id;
end $$;

create or replace function public.toggle_activity_reaction(p_event uuid, p_emoji text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_emoji not in ('🔥', '💀', '🍞', '👀', '🫡', '🎉') then raise exception 'Unknown reaction'; end if;
  if not exists (select 1 from public.activity_events e where e.id = p_event and public.is_member(e.group_id)) then
    raise exception 'Activity not found';
  end if;
  if exists (select 1 from public.activity_reactions where event_id = p_event and user_id = auth.uid() and emoji = p_emoji) then
    delete from public.activity_reactions where event_id = p_event and user_id = auth.uid() and emoji = p_emoji;
    return false;
  end if;
  insert into public.activity_reactions (event_id, user_id, emoji) values (p_event, auth.uid(), p_emoji);
  return true;
end $$;

create or replace function public.race_activity(p_group uuid, p_limit int default 30, p_offset int default 0)
returns table (
  id uuid, event_type text, actor_user_id uuid, display_name text, avatar text, colour text,
  company_name text, interview_round int, metadata jsonb, created_at timestamptz,
  reactions jsonb
) language sql stable security definer set search_path = public as $$
  select e.id, e.event_type, e.actor_user_id, m.display_name, m.avatar, m.colour,
         e.company_name, e.interview_round, e.metadata, e.created_at,
         coalesce((select jsonb_object_agg(r.emoji, r.n) from (
           select emoji, count(*)::int as n from public.activity_reactions where event_id = e.id group by emoji
         ) r), '{}'::jsonb)
    from public.activity_events e join public.memberships m on m.group_id = e.group_id and m.user_id = e.actor_user_id
   where e.group_id = p_group and public.is_member(p_group)
   order by e.created_at desc
   limit least(greatest(coalesce(p_limit, 30), 1), 60) offset greatest(coalesce(p_offset, 0), 0)
$$;

revoke all on public.interviews, public.activity_events, public.activity_reactions from anon, authenticated;
grant select on public.interviews, public.activity_events, public.activity_reactions to authenticated;
grant execute on function public.race_leaderboard(uuid, text), public.quick_log_application(uuid, text),
  public.quick_log_interview(uuid, text, int), public.update_interview(uuid, text, int), public.rename_application(uuid, text), public.remove_application(uuid), public.remove_interview(uuid),
  public.confirm_employment(uuid, text), public.correct_employment(uuid), public.toggle_activity_reaction(uuid, text),
  public.race_activity(uuid, int, int) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.interviews;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.activity_events;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.activity_reactions;
exception when duplicate_object then null; end $$;
