-- Evzon baseline, applied using the Supabase migration API.
-- Only user JWTs are used by the app; no service-role key.
create schema if not exists evzon_private;
revoke all on schema evzon_private from public,anon;
grant usage on schema evzon_private to authenticated;
create table evzon_private.admin_bootstrap(email text primary key);
insert into evzon_private.admin_bootstrap values('jojosbizareavantures@gmail.com');
create table public.evzon_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 100), email text not null,
 role text not null default 'REFERRER' check(role in ('ADMIN','REFERRER')),
 status text not null default 'Pending' check(status in ('Pending','Approved','Suspended')),
 code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
 payout_preference text not null default '' check(length(payout_preference)<=200),created_at timestamptz not null default now()
);
create table public.evzon_workspace(id boolean primary key default true check(id),state jsonb,revision bigint not null default 0,updated_at timestamptz not null default now(),updated_by uuid references public.evzon_profiles(id));
insert into public.evzon_workspace(id) values(true);
create table public.evzon_referral_config (
 id boolean primary key default true check(id),hire_bonus numeric not null default 20 check(hire_bonus between 0 and 100000),
 retention_bonus numeric not null default 30 check(retention_bonus between 0 and 100000),retention_days int not null default 30 check(retention_days between 1 and 365),
 commission_rate numeric not null default 5 check(commission_rate between 0 and 100),commission_months int not null default 6 check(commission_months between 1 and 60),require_collected boolean not null default true,
 resources text not null default E'Candidate requirements\nAdults aged 18 or older, reliable internet, clear written English, discretion and reliable attendance.\n\nSelection and training\nApplication → interview → training → assessment → company hiring decision. Only the company handles agency relationships.\n\nStrong referrals\nExplain the role accurately. Get the candidate’s permission before sharing contact details. Recommend reliable people.\n\nRewards\nA hire bonus requires completed training, a passed assessment and an active hire. Retention counts approved days actually worked, not calendar days. Monthly commissions use positive worker contribution and are reviewed after the period closes.\n\nFAQ\nSubmitting a candidate does not guarantee hiring or a reward. Duplicate applications do not create additional attribution. Ask an administrator to review an incorrect attribution. Payment follows review and applicable cash collection.\n\nAccount safety\nNever submit agency passwords or banking credentials in this portal.',updated_at timestamptz not null default now()
);
insert into public.evzon_referral_config(id) values(true);
create table public.evzon_referrals (
 id uuid primary key default gen_random_uuid(),referrer_id uuid not null references public.evzon_profiles(id),candidate_name text not null check(length(candidate_name) between 1 and 120),worker_id text unique,source text not null default 'Referral link',
 stage text not null default 'Submitted' check(stage in ('Submitted','Under Review','Interview','Training','Training Completed','Hired','Active','30-Day Milestone Completed','Rejected','Withdrawn')),
 training_complete boolean not null default false,assessment_passed boolean not null default false,hired_on date,worker_status text not null default '',active_days int not null default 0,terms jsonb not null,reason text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index evzon_referrals_referrer_idx on public.evzon_referrals(referrer_id,created_at);
create table evzon_private.contacts(referral_id uuid primary key references public.evzon_referrals(id) on delete cascade,email text unique,phone text not null default '',notes text not null default '');
create table public.evzon_rewards (
 id uuid primary key default gen_random_uuid(),referral_id uuid not null references public.evzon_referrals(id),referrer_id uuid not null references public.evzon_profiles(id),worker_id text not null,
 kind text not null check(kind in ('Hire','Retention','Commission')),period date not null,amount numeric not null default 0 check(amount>=0),
 status text not null default 'Not yet eligible' check(status in ('Not yet eligible','Pending review','Approved','Payable','Paid','Rejected','Cancelled')),
 explanation text not null,terms jsonb not null,earned_at timestamptz,approved_at timestamptz,approved_by uuid references public.evzon_profiles(id),paid_at timestamptz,paid_by uuid references public.evzon_profiles(id),payment_reference text not null default '',reason text not null default '',created_at timestamptz not null default now(),unique(worker_id,kind,period)
);
create unique index evzon_rewards_milestone_unique on public.evzon_rewards(worker_id,kind) where kind in ('Hire','Retention');
create index evzon_rewards_referrer_idx on public.evzon_rewards(referrer_id,period);
create index evzon_rewards_referral_idx on public.evzon_rewards(referral_id);
create index evzon_rewards_status_idx on public.evzon_rewards(status,period);
create table public.evzon_events(id uuid primary key default gen_random_uuid(),referrer_id uuid not null references public.evzon_profiles(id),referral_id uuid references public.evzon_referrals(id),message text not null,created_at timestamptz not null default now());
create index evzon_events_referrer_idx on public.evzon_events(referrer_id,created_at desc);
create index evzon_events_referral_idx on public.evzon_events(referral_id);
create table evzon_private.audit(id uuid primary key default gen_random_uuid(),actor uuid references public.evzon_profiles(id),action text not null,before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
create table evzon_private.periods(worker_id text not null,period date not null,revenue numeric not null check(revenue>=0),compensation numeric not null check(compensation>=0),invoices text[] not null,finalized_by uuid not null references public.evzon_profiles(id),finalized_at timestamptz not null default now(),primary key(worker_id,period));
create table evzon_private.workday_exceptions(worker_id text not null,day date not null check(day<=current_date),reason text not null check(length(reason)>=8),approved_by uuid not null references public.evzon_profiles(id),primary key(worker_id,day));
create table evzon_private.payouts(reward_id uuid primary key references public.evzon_rewards(id),amount numeric not null,reference text not null,paid_by uuid not null references public.evzon_profiles(id),paid_at timestamptz not null default now());
create function evzon_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.evzon_profiles where id=auth.uid() and role='ADMIN' and status='Approved');$$;
create function evzon_private.is_approved() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.evzon_profiles where id=auth.uid() and status='Approved');$$;
create function evzon_private.profile_created() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.evzon_profiles(id,name,email) values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''),split_part(new.email,'@',1),'Referrer'),100),coalesce(new.email,'')) on conflict(id) do update set email=excluded.email;
 if new.email_confirmed_at is not null and exists(select 1 from evzon_private.admin_bootstrap where email=lower(new.email)) then
  update public.evzon_profiles set role='ADMIN',status='Approved' where id=new.id;
  delete from evzon_private.admin_bootstrap where email=lower(new.email);
 end if;
 return new;
end $$;
create trigger evzon_profile_created after insert or update of email_confirmed_at,email on auth.users for each row execute function evzon_private.profile_created();
alter table public.evzon_profiles enable row level security;
alter table public.evzon_workspace enable row level security;
alter table public.evzon_referral_config enable row level security;
alter table public.evzon_referrals enable row level security;
alter table public.evzon_rewards enable row level security;
alter table public.evzon_events enable row level security;
alter table evzon_private.contacts enable row level security;
alter table evzon_private.admin_bootstrap enable row level security;
alter table evzon_private.audit enable row level security;
alter table evzon_private.periods enable row level security;
alter table evzon_private.workday_exceptions enable row level security;
alter table evzon_private.payouts enable row level security;
revoke all on all tables in schema evzon_private from public,anon,authenticated;
revoke all on public.evzon_profiles,public.evzon_workspace,public.evzon_referral_config,public.evzon_referrals,public.evzon_rewards,public.evzon_events from public,anon,authenticated;
grant select on public.evzon_profiles,public.evzon_workspace,public.evzon_referral_config,public.evzon_referrals,public.evzon_rewards,public.evzon_events to authenticated;
create policy profile_read on public.evzon_profiles for select to authenticated using(id=(select auth.uid()) or (select evzon_private.is_admin()));
create policy workspace_read on public.evzon_workspace for select to authenticated using((select evzon_private.is_admin()));
create policy config_read on public.evzon_referral_config for select to authenticated using((select auth.uid()) is not null);
create policy referrals_read on public.evzon_referrals for select to authenticated using((select evzon_private.is_admin()) or (referrer_id=(select auth.uid()) and (select evzon_private.is_approved())));
create policy rewards_read on public.evzon_rewards for select to authenticated using((select evzon_private.is_admin()) or (referrer_id=(select auth.uid()) and (select evzon_private.is_approved())));
create policy events_read on public.evzon_events for select to authenticated using((select evzon_private.is_admin()) or (referrer_id=(select auth.uid()) and (select evzon_private.is_approved())));
create function evzon_private.terms() returns jsonb language sql stable set search_path='' as $$select to_jsonb(c)-'id'-'resources'-'updated_at' from public.evzon_referral_config c where id;$$;
create function evzon_private.audit(p_action text,p_before jsonb default null,p_after jsonb default null) returns void language sql set search_path='' as $$insert into evzon_private.audit(actor,action,before_data,after_data) values(auth.uid(),p_action,p_before,p_after);$$;
create function evzon_private.collected(p_worker text,p_period date) returns boolean language plpgsql stable set search_path='' as $$
declare p evzon_private.periods; s jsonb; inv text; total numeric; paid numeric;
begin
 select * into p from evzon_private.periods where worker_id=p_worker and period=p_period;
 if not found or cardinality(p.invoices)=0 then return false; end if;
 select state into s from public.evzon_workspace where id;
 foreach inv in array p.invoices loop
  select (x->>'amount')::numeric into total from jsonb_array_elements(s->'invoices') x where x->>'id'=inv;
  if total is null then return false; end if;
  select coalesce(sum((x->>'amount')::numeric),0) into paid from jsonb_array_elements(s->'payments') x where x->>'invoice'=inv and (x->>'date')::date<=current_date;
  if paid<total then return false; end if;
 end loop;
 return true;
end $$;
create function evzon_private.refresh_rewards() returns void language plpgsql set search_path='' as $$
declare r public.evzon_referrals; s jsonb; w jsonb; days int; eligible boolean; p evzon_private.periods; amount numeric; exp text; added uuid;
begin
 select state into s from public.evzon_workspace where id;
 for r in select * from public.evzon_referrals where worker_id is not null loop
  select x into w from jsonb_array_elements(s->'workers') x where x->>'id'=r.worker_id;
  select count(*) into days from (
   select (x->>'date')::date as day from jsonb_array_elements(s->'shifts') x
   where coalesce(nullif(x->>'replacement',''),x->>'worker')=r.worker_id and (x->>'approved')::boolean
   and (not coalesce((x->>'absence')::boolean,false) or coalesce(x->>'replacement','')<>'')
   and coalesce((x->>'actual')::numeric,0)+coalesce((x->>'overtime')::numeric,0)>0 and (x->>'date')::date between r.hired_on and current_date
   union select day from evzon_private.workday_exceptions where worker_id=r.worker_id and day between r.hired_on and current_date
  ) worked;
  update public.evzon_referrals set worker_status=coalesce(w->>'status','Terminated'),active_days=days where id=r.id;
  eligible:=r.training_complete and r.assessment_passed and r.hired_on<=current_date and w->>'status'='Active' and r.stage not in ('Rejected','Withdrawn');
  insert into public.evzon_rewards(referral_id,referrer_id,worker_id,kind,period,explanation,terms)
   values(r.id,r.referrer_id,r.worker_id,'Hire',date_trunc('month',coalesce(r.hired_on,current_date))::date,'Training completed, assessment passed and active hiring required.',r.terms) on conflict do nothing;
  insert into public.evzon_rewards(referral_id,referrer_id,worker_id,kind,period,explanation,terms)
   values(r.id,r.referrer_id,r.worker_id,'Retention',date_trunc('month',coalesce(r.hired_on,current_date))::date,'Requires approved active working days and continued active employment.',r.terms) on conflict do nothing;
  if eligible then
   update public.evzon_rewards set status='Pending review',amount=(terms->>'hire_bonus')::numeric,earned_at=now(),period=date_trunc('month',current_date),explanation='Training completed, assessment passed and worker hired.' where worker_id=r.worker_id and kind='Hire' and status='Not yet eligible' returning id into added;
   if added is not null then insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,'Hire bonus earned for '||r.candidate_name||'; awaiting review.'); end if;
   if days>=(r.terms->>'retention_days')::int then
    update public.evzon_rewards set status='Pending review',amount=(terms->>'retention_bonus')::numeric,earned_at=now(),period=date_trunc('month',current_date),explanation='Worker completed '||(terms->>'retention_days')||' approved active working days.' where worker_id=r.worker_id and kind='Retention' and status='Not yet eligible' returning id into added;
    if added is not null then insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,'Retention milestone reached by '||r.candidate_name||'.'); end if;
   end if;
  end if;
  if r.hired_on is not null and r.training_complete and r.assessment_passed then
   for p in select * from evzon_private.periods where worker_id=r.worker_id and period>=date_trunc('month',r.hired_on) and period<date_trunc('month',r.hired_on)+make_interval(months=>(r.terms->>'commission_months')::int) loop
    amount:=greatest(0,p.revenue-p.compensation)*(r.terms->>'commission_rate')::numeric/100;
    if amount>0 then
     exp:=(r.terms->>'commission_rate')||'% of $'||(p.revenue-p.compensation)::text||' eligible worker contribution for '||to_char(p.period,'FMMonth YYYY')||'.';
     insert into public.evzon_rewards(referral_id,referrer_id,worker_id,kind,period,amount,status,explanation,terms,earned_at)
      values(r.id,r.referrer_id,r.worker_id,'Commission',p.period,amount,'Pending review',exp,r.terms,now()) on conflict do nothing returning id into added;
     if added is not null then insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,'Monthly commission earned for '||r.candidate_name||' ('||to_char(p.period,'YYYY-MM')||').'); end if;
    end if;
   end loop;
  end if;
 end loop;
 update public.evzon_rewards set status='Payable' where status='Approved' and (kind<>'Commission' or not (terms->>'require_collected')::boolean or evzon_private.collected(worker_id,period));
end $$;
create function evzon_private.validate_workspace(s jsonb) returns void language plpgsql set search_path='' as $$
declare k text; a jsonb; x jsonb; f text; v jsonb;
begin
 if s->>'version'<>'1' or jsonb_typeof(s->'settings')<>'object' or octet_length(s::text)>3500000 then raise exception 'EVZON_INVALID: Invalid workspace'; end if;
 foreach k in array array['workers','team','expenses','agencies','invoices','payments','actualExpenses','shifts','applicants','history','snapshots','earnings','scenarios'] loop
  a:=s->k;
  if a is null or jsonb_typeof(a)<>'array' then raise exception 'EVZON_INVALID: Missing collection'; end if;
  if (select count(*)<>count(distinct e->>'id') from jsonb_array_elements(a) e) then raise exception 'EVZON_INVALID: Duplicate identifiers'; end if;
  for x in select * from jsonb_array_elements(a) loop
   if coalesce(x->>'id','')='' or jsonb_typeof(x)<>'object' then raise exception 'EVZON_INVALID: Missing identifier'; end if;
   for f,v in select * from jsonb_each(x) loop
    if jsonb_typeof(v)='number' and k not in ('snapshots','history') and (v::numeric<0 or v::numeric>1000000000000) then raise exception 'EVZON_INVALID: Financial value out of range'; end if;
   end loop;
  end loop;
 end loop;
 for x in select * from jsonb_array_elements(s->'workers') loop
  if x->>'status' not in ('Active','Training','Inactive','Terminated') or x->>'payroll' not in ('Monthly salary','Approved hours') then raise exception 'EVZON_INVALID: Unsupported worker model'; end if;
 end loop;
end $$;
create function evzon_private.sync_workers(s jsonb) returns void language plpgsql set search_path='' as $$
declare w jsonb; r public.evzon_referrals; before_r jsonb;
begin
 for w in select * from jsonb_array_elements(s->'workers') loop
  select * into r from public.evzon_referrals where worker_id=w->>'id';
  if coalesce(w->>'referrerId','')='' then
   if r.id is not null then
    perform evzon_private.audit('Referral attribution removed',to_jsonb(r),w);
    update public.evzon_referrals set worker_id=null,worker_status='Unlinked',updated_at=now() where id=r.id;
    update public.evzon_rewards set status='Cancelled',reason='Admin removed worker attribution.' where referral_id=r.id and status='Not yet eligible';
   end if;
   continue;
  end if;
  if (r.id is null or r.referrer_id is distinct from (w->>'referrerId')::uuid) and not exists(select 1 from public.evzon_profiles where id=(w->>'referrerId')::uuid and role='REFERRER' and status='Approved') then raise exception 'EVZON_INVALID: Select an approved referrer'; end if;
  if r.id is null and coalesce(w->>'referralId','')<>'' then
   select * into r from public.evzon_referrals where id=(w->>'referralId')::uuid;
   if r.id is null or r.worker_id is not null then raise exception 'EVZON_INVALID: Referral already linked or missing'; end if;
  end if;
  if r.id is null then
   insert into public.evzon_referrals(referrer_id,candidate_name,worker_id,source,terms,training_complete,assessment_passed,hired_on,stage)
    values((w->>'referrerId')::uuid,w->>'name',w->>'id','Admin assignment',evzon_private.terms(),coalesce((w->>'trainingComplete')::boolean,false),coalesce((w->>'assessmentPassed')::boolean,false),case when w->>'status'='Active' then nullif(w->>'start','')::date else null end,case when w->>'status'='Active' then 'Hired' else 'Training' end) returning * into r;
   insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,'Referral linked to a worker by an administrator.');
   perform evzon_private.audit('Worker referral assigned',null,to_jsonb(r));
  else
   if r.referrer_id<>(w->>'referrerId')::uuid or r.worker_id is null then
    before_r:=to_jsonb(r);
    update public.evzon_referrals set referrer_id=(w->>'referrerId')::uuid,worker_id=w->>'id',updated_at=now() where id=r.id returning * into r;
    update public.evzon_rewards set referrer_id=r.referrer_id where referral_id=r.id and status='Not yet eligible';
    perform evzon_private.audit('Worker referral attribution corrected',before_r,to_jsonb(r));
    insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,'Administrator updated worker attribution. Earned rewards keep their original beneficiary and terms.');
   end if;
  end if;
 end loop;
end $$;
create function evzon_private.portal() returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.evzon_profiles; admin boolean; result jsonb;
begin
 if auth.uid() is null then raise exception 'EVZON_FORBIDDEN'; end if;
 select * into me from public.evzon_profiles where id=auth.uid();
 if me.id is null then raise exception 'EVZON_FORBIDDEN'; end if;
 admin:=evzon_private.is_admin();
 select jsonb_build_object('profile',to_jsonb(me),'config',(select to_jsonb(c) from public.evzon_referral_config c where id),
 'profiles',case when admin then (select coalesce(jsonb_agg(to_jsonb(p) order by created_at desc),'[]') from public.evzon_profiles p) else '[]'::jsonb end,
 'referrals',(select coalesce(jsonb_agg(to_jsonb(r) order by created_at desc),'[]') from public.evzon_referrals r where admin or (r.referrer_id=me.id and me.status='Approved')),
 'rewards',(select coalesce(jsonb_agg(to_jsonb(q) order by period desc,created_at desc),'[]') from public.evzon_rewards q where admin or (q.referrer_id=me.id and me.status='Approved')),
 'events',(select coalesce(jsonb_agg(to_jsonb(e) order by created_at desc),'[]') from (select * from public.evzon_events where admin or (referrer_id=me.id and me.status='Approved') order by created_at desc limit 300) e),
 'contacts',case when admin then (select coalesce(jsonb_agg(to_jsonb(c)),'[]') from evzon_private.contacts c) else '[]'::jsonb end,
 'periods',case when admin then (select coalesce(jsonb_agg(to_jsonb(p)),'[]') from evzon_private.periods p) else '[]'::jsonb end,
 'audit',case when admin then (select coalesce(jsonb_agg(to_jsonb(a) order by created_at desc),'[]') from (select id,actor,action,created_at from evzon_private.audit order by created_at desc limit 200) a) else '[]'::jsonb end) into result;
 return result;
end $$;
create function evzon_private.command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.evzon_profiles; p public.evzon_profiles; r public.evzon_referrals; q public.evzon_rewards; s jsonb; old jsonb; rev bigint; rid uuid; period_start date; revenue numeric; comp numeric; invs text[];
begin
 if auth.uid() is null then raise exception 'EVZON_FORBIDDEN'; end if;
 select * into me from public.evzon_profiles where id=auth.uid();
 if me.id is null or me.status='Suspended' then raise exception 'EVZON_FORBIDDEN'; end if;
 perform pg_advisory_xact_lock(782541);
 if p_action='profile' then
  if length(trim(coalesce(p_data->>'name',''))) not between 1 and 100 or length(coalesce(p_data->>'payout_preference',''))>200 then raise exception 'EVZON_INVALID: Check profile fields'; end if;
  update public.evzon_profiles set name=trim(p_data->>'name'),payout_preference=coalesce(p_data->>'payout_preference','') where id=me.id;
  return evzon_private.portal();
 elsif p_action='submit' then
  if me.status<>'Approved' then raise exception 'EVZON_FORBIDDEN'; end if;
  if length(trim(coalesce(p_data->>'name',''))) not between 1 and 120 or coalesce(p_data->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_data->>'email')>254 or length(coalesce(p_data->>'notes',''))>2000 or length(coalesce(p_data->>'phone',''))>60 or not coalesce((p_data->>'consent')::boolean,false) then raise exception 'EVZON_INVALID: Name, email and candidate consent are required'; end if;
  if (select count(*) from public.evzon_referrals where referrer_id=me.id and created_at>now()-interval '1 day')>=30 then raise exception 'EVZON_INVALID: Daily submission limit reached'; end if;
  insert into public.evzon_referrals(referrer_id,candidate_name,source,terms) values(me.id,trim(p_data->>'name'),'Manual referral',evzon_private.terms()) returning id into rid;
  insert into evzon_private.contacts(referral_id,email,phone,notes) values(rid,lower(trim(p_data->>'email')),coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''));
  insert into public.evzon_events(referrer_id,referral_id,message) values(me.id,rid,'Candidate submitted: '||trim(p_data->>'name'));
  return evzon_private.portal();
 end if;
 if not evzon_private.is_admin() then raise exception 'EVZON_FORBIDDEN'; end if;
 select state,revision into s,rev from public.evzon_workspace where id for update;
 if p_action='audit' then
  return jsonb_build_object('audit',(select to_jsonb(a) from evzon_private.audit a where id=(p_data->>'id')::uuid));
 elsif p_action='save' then
  if (p_data->>'revision')::bigint is distinct from rev then raise exception 'EVZON_CONFLICT'; end if;
  old:=s; s:=(p_data->'state')-'referralRewards';
  perform evzon_private.validate_workspace(s);
  if exists(select 1 from evzon_private.periods z where
   (select coalesce(jsonb_agg(x order by x->>'id'),'[]') from jsonb_array_elements(old->'earnings') x where x->>'worker'=z.worker_id and date_trunc('month',(x->>'date')::date)=z.period) is distinct from
   (select coalesce(jsonb_agg(x order by x->>'id'),'[]') from jsonb_array_elements(s->'earnings') x where x->>'worker'=z.worker_id and date_trunc('month',(x->>'date')::date)=z.period)
   or (select coalesce(jsonb_agg(x order by x->>'id'),'[]') from jsonb_array_elements(old->'actualExpenses') x where x->>'worker'=z.worker_id and x->>'category'='Worker payroll' and date_trunc('month',coalesce(nullif(x->>'period','')||'-01',x->>'date')::date)=z.period) is distinct from
   (select coalesce(jsonb_agg(x order by x->>'id'),'[]') from jsonb_array_elements(s->'actualExpenses') x where x->>'worker'=z.worker_id and x->>'category'='Worker payroll' and date_trunc('month',coalesce(nullif(x->>'period','')||'-01',x->>'date')::date)=z.period)) then raise exception 'EVZON_INVALID: A finalized referral payroll period cannot be rewritten'; end if;
  perform evzon_private.sync_workers(s);
  update public.evzon_workspace set state=s,revision=rev+1,updated_at=now(),updated_by=me.id where id;
  perform evzon_private.audit('Workspace saved, revision '||(rev+1),old,s);
 elsif p_action='account' then
  select * into p from public.evzon_profiles where id=(p_data->>'id')::uuid for update;
  if p.id is null or p_data->>'status' not in ('Pending','Approved','Suspended') or p_data->>'role' not in ('ADMIN','REFERRER') then raise exception 'EVZON_INVALID: Account settings'; end if;
  if p.id=me.id then raise exception 'EVZON_INVALID: You cannot change your own access'; end if;
  update public.evzon_profiles set status=p_data->>'status',role=p_data->>'role' where id=p.id;
  perform evzon_private.audit('Account access changed',to_jsonb(p),p_data);
 elsif p_action='referral' then
  select * into r from public.evzon_referrals where id=(p_data->>'id')::uuid for update;
  if r.id is null then raise exception 'EVZON_INVALID: Referral not found'; end if;
  if p_data->>'stage' in ('Rejected','Withdrawn') and length(trim(coalesce(p_data->>'reason','')))<3 then raise exception 'EVZON_INVALID: A reason is required'; end if;
  if nullif(p_data->>'hired_on','')::date>current_date then raise exception 'EVZON_INVALID: Hiring date is in the future'; end if;
  if exists(select 1 from public.evzon_rewards where referral_id=r.id and earned_at is not null) and r.hired_on is distinct from nullif(p_data->>'hired_on','')::date then raise exception 'EVZON_INVALID: Hiring date is locked after a reward is earned'; end if;
  update public.evzon_referrals set stage=p_data->>'stage',training_complete=coalesce((p_data->>'training_complete')::boolean,false),assessment_passed=coalesce((p_data->>'assessment_passed')::boolean,false),hired_on=nullif(p_data->>'hired_on','')::date,reason=coalesce(p_data->>'reason',''),updated_at=now() where id=r.id;
  perform evzon_private.audit('Referral milestones updated',to_jsonb(r),p_data);
  insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,r.candidate_name||': '||(p_data->>'stage')||case when coalesce((p_data->>'training_complete')::boolean,false) and not r.training_complete then ' · training completed' else '' end);
 elsif p_action='workday' then
  if not exists(select 1 from public.evzon_referrals where worker_id=p_data->>'worker_id' and hired_on<=(p_data->>'day')::date) then raise exception 'EVZON_INVALID: Workday must be on or after hiring'; end if;
  insert into evzon_private.workday_exceptions(worker_id,day,reason,approved_by) values(p_data->>'worker_id',(p_data->>'day')::date,p_data->>'reason',me.id);
  perform evzon_private.audit('Active day exception approved',null,p_data);
 elsif p_action='finalize' then
  period_start:=date_trunc('month',(p_data->>'period')::date)::date;
  if period_start>=date_trunc('month',current_date) then raise exception 'EVZON_INVALID: Only completed months can be finalized'; end if;
  if not coalesce((p_data->>'confirmed')::boolean,false) or not exists(select 1 from public.evzon_referrals where worker_id=p_data->>'worker_id') then raise exception 'EVZON_INVALID: Confirm all worker compensation is accounted for'; end if;
  select coalesce(sum((x->>'hourly')::numeric+(x->>'commission')::numeric),0),array_agg(distinct x->>'invoice') into revenue,invs from jsonb_array_elements(s->'earnings') x where x->>'worker'=p_data->>'worker_id' and date_trunc('month',(x->>'date')::date)=period_start;
  if revenue>0 and (invs is null or array_position(invs,null) is not null or array_position(invs,'') is not null) then raise exception 'EVZON_INVALID: Link all earned revenue to invoices before finalizing'; end if;
  if exists(select 1 from unnest(invs) i where not exists(select 1 from jsonb_array_elements(s->'invoices') x where x->>'id'=i)) then raise exception 'EVZON_INVALID: Linked invoice is missing'; end if;
  if exists(select 1 from unnest(invs) i where (select coalesce(sum((x->>'hourly')::numeric+(x->>'commission')::numeric),0) from jsonb_array_elements(s->'earnings') x where x->>'invoice'=i)>(select (x->>'amount')::numeric from jsonb_array_elements(s->'invoices') x where x->>'id'=i)) then raise exception 'EVZON_INVALID: Earned revenue linked to an invoice exceeds its total'; end if;
  select coalesce(sum((x->>'amount')::numeric),0) into comp from jsonb_array_elements(s->'actualExpenses') x where x->>'worker'=p_data->>'worker_id' and x->>'category'='Worker payroll' and date_trunc('month',coalesce(nullif(x->>'period','')||'-01',x->>'date')::date)=period_start;
  insert into evzon_private.periods(worker_id,period,revenue,compensation,invoices,finalized_by) values(p_data->>'worker_id',period_start,revenue,comp,coalesce(invs,'{}'),me.id) on conflict do nothing;
  perform evzon_private.audit('Referral contribution period finalized',null,p_data);
 elsif p_action='reward' then
  select * into q from public.evzon_rewards where id=(p_data->>'id')::uuid for update;
  if q.id is null then raise exception 'EVZON_INVALID: Reward not found'; end if;
  if q.status='Paid' and p_data->>'status'='Paid' then return evzon_private.portal(); end if;
  if q.status in ('Paid','Rejected','Cancelled','Not yet eligible') then raise exception 'EVZON_INVALID: This reward cannot be processed'; end if;
  if p_data->>'status' not in ('Pending review','Approved','Payable','Paid','Rejected','Cancelled') then raise exception 'EVZON_INVALID: Reward status'; end if;
  if p_data->>'status' in ('Rejected','Cancelled') and length(trim(coalesce(p_data->>'reason','')))<3 then raise exception 'EVZON_INVALID: A reason is required'; end if;
  if p_data->>'status' in ('Payable','Paid') and q.status not in ('Approved','Payable') then raise exception 'EVZON_INVALID: Approve the reward before payment'; end if;
  if p_data->>'status' in ('Payable','Paid') and q.kind='Commission' and (q.terms->>'require_collected')::boolean and not evzon_private.collected(q.worker_id,q.period) then raise exception 'EVZON_INVALID: Associated agency invoices must be fully collected'; end if;
  if p_data->>'status'='Paid' and length(trim(coalesce(p_data->>'payment_reference','')))<3 then raise exception 'EVZON_INVALID: A payment reference is required'; end if;
  update public.evzon_rewards set status=p_data->>'status',reason=coalesce(p_data->>'reason',''),
   approved_at=case when p_data->>'status' in ('Approved','Payable','Paid') then coalesce(approved_at,now()) else approved_at end,
   approved_by=case when p_data->>'status' in ('Approved','Payable','Paid') then coalesce(approved_by,me.id) else approved_by end,
   paid_at=case when p_data->>'status'='Paid' then now() else null end,paid_by=case when p_data->>'status'='Paid' then me.id else null end,
   payment_reference=case when p_data->>'status'='Paid' then p_data->>'payment_reference' else payment_reference end where id=q.id;
  if p_data->>'status'='Paid' then insert into evzon_private.payouts(reward_id,amount,reference,paid_by) values(q.id,q.amount,p_data->>'payment_reference',me.id); end if;
  perform evzon_private.audit('Referral reward '||(p_data->>'status'),to_jsonb(q),p_data);
  insert into public.evzon_events(referrer_id,referral_id,message) values(q.referrer_id,q.referral_id,q.kind||' reward: '||(p_data->>'status')||' · $'||q.amount::text);
 elsif p_action='config' then
  select to_jsonb(c) into old from public.evzon_referral_config c where id;
  update public.evzon_referral_config set hire_bonus=(p_data->>'hire_bonus')::numeric,retention_bonus=(p_data->>'retention_bonus')::numeric,retention_days=(p_data->>'retention_days')::int,commission_rate=(p_data->>'commission_rate')::numeric,commission_months=(p_data->>'commission_months')::int,require_collected=(p_data->>'require_collected')::boolean,resources=left(p_data->>'resources',20000),updated_at=now() where id;
  perform evzon_private.audit('Referral defaults changed prospectively',old,p_data);
 elsif p_action<>'refresh' then raise exception 'EVZON_INVALID: Unknown action';
 end if;
 perform evzon_private.refresh_rewards();
 return evzon_private.portal() || jsonb_build_object('workspace',(select to_jsonb(ws) from public.evzon_workspace ws where id));
exception when unique_violation then raise exception 'EVZON_INVALID: This candidate, workday or reward is already recorded';
end $$;
-- Deliberately anonymous, write-only application endpoint. No caller-supplied referrer ID is accepted.
create function evzon_private.apply(p_code text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.evzon_profiles; rid uuid;
begin
 select * into p from public.evzon_profiles where code=upper(p_code) and status='Approved' and role='REFERRER';
 if p.id is null then raise exception 'EVZON_INVALID: Referral link is unavailable'; end if;
 if coalesce(p_data->>'website','')<>'' then return '{"submitted":true}'::jsonb; end if;
 if length(trim(coalesce(p_data->>'name',''))) not between 1 and 120 or coalesce(p_data->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_data->>'email')>254 or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'notes',''))>2000 or not coalesce((p_data->>'consent')::boolean,false) or not coalesce((p_data->>'adult')::boolean,false) then raise exception 'EVZON_INVALID: Complete the required fields and confirmations'; end if;
 perform pg_advisory_xact_lock(hashtext(p.id::text));
 if (select count(*) from public.evzon_referrals where referrer_id=p.id and created_at>now()-interval '1 day')>=30 then raise exception 'EVZON_INVALID: Submission limit reached; please try tomorrow'; end if;
 if exists(select 1 from evzon_private.contacts where email=lower(trim(p_data->>'email'))) then return '{"submitted":true}'::jsonb; end if;
 insert into public.evzon_referrals(referrer_id,candidate_name,source,terms) values(p.id,trim(p_data->>'name'),'Referral link',evzon_private.terms()) returning id into rid;
 insert into evzon_private.contacts(referral_id,email,phone,notes) values(rid,lower(trim(p_data->>'email')),coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''));
 insert into public.evzon_events(referrer_id,referral_id,message) values(p.id,rid,'New application received: '||trim(p_data->>'name'));
 return '{"submitted":true}'::jsonb;
exception when unique_violation then return '{"submitted":true}'::jsonb;
end $$;
create function public.evzon_portal() returns jsonb language sql security invoker set search_path='' as $$select evzon_private.portal();$$;
create function public.evzon_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select evzon_private.command(p_action,p_data);$$;
create function public.evzon_apply(p_code text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select evzon_private.apply(p_code,p_data);$$;
revoke execute on all functions in schema evzon_private from public,anon,authenticated;
revoke execute on function public.evzon_portal(),public.evzon_command(text,jsonb),public.evzon_apply(text,jsonb) from public,anon,authenticated;
grant execute on function evzon_private.is_admin(),evzon_private.is_approved(),evzon_private.portal(),evzon_private.command(text,jsonb) to authenticated;
grant usage on schema evzon_private to anon;
grant execute on function evzon_private.apply(text,jsonb) to anon,authenticated;
grant execute on function public.evzon_portal(),public.evzon_command(text,jsonb) to authenticated;
grant execute on function public.evzon_apply(text,jsonb) to anon,authenticated;
