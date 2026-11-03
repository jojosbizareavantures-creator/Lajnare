-- Private curriculum and study progress. Exposed functions validate the current profile on every call.
create table evzon_private.training_units(
 id text primary key check(id ~ '^[a-z0-9-]{1,80}$'),
 day int not null references public.evzon_chatter_lessons(day),
 section text not null check(length(section) between 1 and 160),
 title text not null check(length(title) between 1 and 200),title_mk text not null default '' check(length(title_mk)<=200),
 summary text not null default '' check(length(summary)<=1000),
 body text not null check(length(body) between 1 and 40000),body_mk text not null default '' check(length(body_mk)<=40000),
 note text not null default '' check(length(note)<=2000),assets jsonb not null default '[]' check(jsonb_typeof(assets)='array'),
 position int not null,minutes int not null check(minutes between 1 and 240),published boolean not null default false,
 revision int not null default 1 check(revision>0),source text not null default '',updated_at timestamptz not null default now()
);
create index training_units_day_position on evzon_private.training_units(day,position);
create table evzon_private.training_reads(
 chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,
 unit_id text not null references evzon_private.training_units(id) on delete cascade,
 revision int not null,read_at timestamptz not null default now(),notes text not null default '' check(length(notes)<=2000),
 primary key(chatter_id,unit_id)
);
create index training_reads_unit on evzon_private.training_reads(unit_id);
alter table evzon_private.training_units enable row level security;
alter table evzon_private.training_reads enable row level security;
revoke all on evzon_private.training_units,evzon_private.training_reads from public,anon,authenticated;

create function evzon_private.training_day_access(p_day int) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
 evzon_private.is_admin() or (
 evzon_private.is_chatter() and exists(
 select 1 from public.evzon_chatter_accounts a join public.evzon_chatter_lessons l on l.day=p_day
 where a.id=auth.uid() and a.completed_at is null and not a.must_change_password and l.published
 and (now() at time zone 'Europe/Skopje')::date>=a.training_start+p_day-1
 and (select count(*) from public.evzon_chatter_progress p where p.chatter_id=a.id and p.day<p_day and p.status='Approved')=p_day-1
 )))
$$;

create function evzon_private.training_portal() returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin();a public.evzon_chatter_accounts;begin
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 select * into a from public.evzon_chatter_accounts where id=auth.uid();
 if not admin and (a.id is null or a.must_change_password) then raise exception 'EVZON_FORBIDDEN';end if;
 return jsonb_build_object(
 'units',(select coalesce(jsonb_agg((to_jsonb(u)-'body'-'body_mk'-'assets'-'note')||jsonb_build_object(
 'unlocked',evzon_private.training_day_access(u.day),
 'body',case when evzon_private.training_day_access(u.day) then u.body else '' end,
 'body_mk',case when evzon_private.training_day_access(u.day) then u.body_mk else '' end,
 'note',case when evzon_private.training_day_access(u.day) then u.note else '' end,
 'assets',case when evzon_private.training_day_access(u.day) then u.assets else '[]'::jsonb end
 ) order by u.position),'[]') from evzon_private.training_units u join public.evzon_chatter_lessons l on l.day=u.day
 where admin or (u.published and l.published and a.completed_at is null)),
 'reads',(select coalesce(jsonb_agg(to_jsonb(r) order by r.read_at),'[]') from evzon_private.training_reads r where admin or (r.chatter_id=auth.uid() and a.completed_at is null))
 );
end $$;

create function evzon_private.training_command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin();u evzon_private.training_units;begin
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>150000 then raise exception 'EVZON_INVALID: Invalid training request';end if;
 perform pg_advisory_xact_lock(782541);
 select * into u from evzon_private.training_units where id=p_data->>'id' for update;
 if u.id is null then raise exception 'EVZON_INVALID: Chapter not found';end if;
 if p_action='read' then
  if admin or not u.published or not evzon_private.training_day_access(u.day) then raise exception 'EVZON_FORBIDDEN';end if;
  if (p_data->>'revision')::int is distinct from u.revision then raise exception 'EVZON_INVALID: This chapter changed. Refresh and review it again';end if;
  if length(coalesce(p_data->>'notes',''))>2000 then raise exception 'EVZON_INVALID: Keep your note under 2,000 characters';end if;
  insert into evzon_private.training_reads(chatter_id,unit_id,revision,notes) values(auth.uid(),u.id,u.revision,trim(coalesce(p_data->>'notes','')))
   on conflict(chatter_id,unit_id) do update set revision=excluded.revision,notes=excluded.notes,read_at=now();
 elsif p_action='edit-unit' and admin then
  if (p_data->>'revision')::int is distinct from u.revision then raise exception 'EVZON_INVALID: Another administrator changed this chapter. Refresh before saving';end if;
  if length(trim(coalesce(p_data->>'title',''))) not between 1 and 200 or length(trim(coalesce(p_data->>'body',''))) not between 1 and 40000 then raise exception 'EVZON_INVALID: A chapter needs a title and 1–40,000 characters of content';end if;
  update evzon_private.training_units set title=trim(p_data->>'title'),title_mk=coalesce(p_data->>'title_mk',''),body=trim(p_data->>'body'),body_mk=coalesce(p_data->>'body_mk',''),note=coalesce(p_data->>'note',''),summary=coalesce(p_data->>'summary',''),published=coalesce((p_data->>'published')::boolean,false),revision=revision+1,updated_at=now() where id=u.id;
  perform evzon_private.audit('Training chapter updated',to_jsonb(u),p_data||jsonb_build_object('revision',u.revision+1));
 else raise exception 'EVZON_FORBIDDEN';end if;
 return evzon_private.training_portal();
end $$;

create function evzon_private.training_asset(p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from evzon_private.training_units u
 where (u.published or evzon_private.is_admin()) and evzon_private.training_day_access(u.day)
 and exists(select 1 from jsonb_array_elements(u.assets) x where x->>'name'=p_name));
$$;

-- The same guard applies to API calls, direct RPC calls, submissions and trainer approvals.
create function evzon_private.require_training_reads() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.day<=4 and new.status in ('Submitted','Approved') then
  if not exists(select 1 from evzon_private.training_units where day=new.day and published) then raise exception 'EVZON_INVALID: Your trainer has not published the chapters for this day';end if;
  if exists(select 1 from evzon_private.training_units u where u.day=new.day and u.published and not exists(
   select 1 from evzon_private.training_reads r where r.chatter_id=new.chatter_id and r.unit_id=u.id and r.revision=u.revision
  )) then raise exception 'EVZON_INVALID: Study and mark every chapter complete before this day can be reviewed';end if;
 end if;
 return new;
end $$;
create trigger require_training_reads before insert or update on public.evzon_chatter_progress for each row execute function evzon_private.require_training_reads();

create function public.evzon_training_portal() returns jsonb language sql security invoker set search_path='' as $$select evzon_private.training_portal();$$;
create function public.evzon_training_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select evzon_private.training_command(p_action,p_data);$$;
create function public.evzon_training_asset(p_name text) returns boolean language sql security invoker set search_path='' as $$select evzon_private.training_asset(p_name);$$;
revoke all on function evzon_private.training_day_access(int),evzon_private.training_portal(),evzon_private.training_command(text,jsonb),evzon_private.training_asset(text),evzon_private.require_training_reads(),public.evzon_training_portal(),public.evzon_training_command(text,jsonb),public.evzon_training_asset(text) from public,anon,authenticated;
grant execute on function evzon_private.training_portal(),evzon_private.training_command(text,jsonb),evzon_private.training_asset(text),public.evzon_training_portal(),public.evzon_training_command(text,jsonb),public.evzon_training_asset(text) to authenticated;
