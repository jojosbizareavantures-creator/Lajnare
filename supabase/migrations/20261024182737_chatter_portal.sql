-- Chatter portal. All writes are authorized inside private functions.
alter table public.evzon_profiles drop constraint evzon_profiles_role_check;
alter table public.evzon_profiles add constraint evzon_profiles_role_check check(role in ('ADMIN','REFERRER','CHATTER'));
create table public.evzon_chatter_accounts(
 id uuid primary key references public.evzon_profiles(id) on delete cascade,
 worker_id text not null unique, training_start date not null,
 completed_at timestamptz, hired_at timestamptz,
 must_change_password boolean not null default true,
 created_by uuid not null references public.evzon_profiles(id),created_at timestamptz not null default now()
);
create table public.evzon_chatter_lessons(day integer primary key check(day between 1 and 7),title text not null check(length(title) between 1 and 160),title_mk text not null default '',content text not null default '' check(length(content)<=40000),content_mk text not null default '' check(length(content_mk)<=40000),published boolean not null default false);
insert into public.evzon_chatter_lessons(day,title,title_mk,content,content_mk,published) values
(1,'Study · Day 1','Учење · Ден 1','','',false),(2,'Study · Day 2','Учење · Ден 2','','',false),(3,'Study · Day 3','Учење · Ден 3','','',false),(4,'Study · Day 4','Учење · Ден 4','','',false),
(5,'Exam & first shadowing','Испит и прво набљудување','Take the knowledge exam before shadowing. Passing the exam confirms your hiring milestone. Then observe an experienced team member and discuss the workflow with your trainer.','Положете го испитот пред набљудувањето. Положениот испит ја потврдува вашата фаза на вработување. Потоа набљудувајте искусен член и разговарајте со обучувачот за работниот процес.',true),
(6,'Guided shadowing','Набљудување со обучувач','Observe a live shift with your trainer. Ask questions, take notes and review the feedback from your previous day. Your trainer will confirm completion.','Набљудувајте смена со обучувачот. Поставувајте прашања, правете белешки и разгледајте ги повратните информации од претходниот ден. Обучувачот ќе го потврди завршувањето.',true),
(7,'Trial shift with the CEO','Пробна смена со директорот','Join the agreed Discord call and share your screen with the CEO during your trial shift. You will receive live guidance, corrections and feedback. Independent work begins after the CEO approves your trial and all seven training days are complete.','Приклучете се на договорениот повик на Discord и споделете го екранот со директорот за време на пробната смена. Ќе добивате насоки, корекции на грешките и повратни информации во реално време. Самостојната работа започнува откако директорот ќе ја одобри пробната смена и ќе бидат завршени сите седум дена обука.',true);
create table public.evzon_chatter_progress(id uuid primary key default gen_random_uuid(),chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,day int not null references public.evzon_chatter_lessons(day),status text not null check(status in ('Submitted','Approved','Changes needed')),feedback text not null default '' check(length(feedback)<=4000),submitted_at timestamptz,approved_at timestamptz,approved_by uuid references public.evzon_profiles(id),unique(chatter_id,day));
create table evzon_private.chatter_config(id boolean primary key default true check(id),pass_score int not null default 80 check(pass_score between 1 and 100),max_attempts int not null default 3 check(max_attempts between 1 and 20),exam_enabled boolean not null default false,questions jsonb not null default '[]',discord_url text not null default '' check(length(discord_url)<=500));
insert into evzon_private.chatter_config(id) values(true);
create table public.evzon_chatter_attempts(id uuid primary key default gen_random_uuid(),chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,score numeric not null,passed boolean not null,created_at timestamptz not null default now());
create table evzon_private.chatter_passwords(id uuid primary key references public.evzon_chatter_accounts(id) on delete cascade,initial_hash text not null);
create table evzon_private.chatter_answers(attempt_id uuid primary key references public.evzon_chatter_attempts(id) on delete cascade,questions jsonb not null,answers jsonb not null);
create table public.evzon_chatter_time(id uuid primary key default gen_random_uuid(),chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,shift_id text,clock_in timestamptz not null default now(),clock_out timestamptz,regular_hours numeric not null default 0 check(regular_hours between 0 and 24),overtime_hours numeric not null default 0 check(overtime_hours between 0 and 24),status text not null default 'Pending' check(status in ('Pending','Approved','Rejected')),notes text not null default '' check(length(notes)<=2000),reviewed_by uuid references public.evzon_profiles(id),check(clock_out is null or clock_out>=clock_in),check(regular_hours+overtime_hours<=24));
create unique index evzon_chatter_one_open_clock on public.evzon_chatter_time(chatter_id) where clock_out is null;
create unique index evzon_chatter_one_approved_shift on public.evzon_chatter_time(shift_id) where status='Approved' and shift_id is not null;
create table public.evzon_chatter_payouts(id uuid primary key default gen_random_uuid(),chatter_id uuid not null references public.evzon_chatter_accounts(id),period date not null check(extract(day from period)=1),amount numeric not null check(amount>0 and amount<=1000000),status text not null default 'Approved' check(status in ('Approved','Paid','Cancelled')),notes text not null default '' check(length(notes)<=2000),paid_at timestamptz,reference text not null default '' check(length(reference)<=200),created_by uuid not null references public.evzon_profiles(id),created_at timestamptz not null default now(),check((status='Paid')=(paid_at is not null)));
create table public.evzon_chatter_announcements(id uuid primary key default gen_random_uuid(),title text not null check(length(title) between 1 and 160),body text not null check(length(body) between 1 and 12000),published boolean not null default true,created_by uuid not null references public.evzon_profiles(id),created_at timestamptz not null default now());
create index chatter_accounts_creator on public.evzon_chatter_accounts(created_by);
create index chatter_progress_reviewer on public.evzon_chatter_progress(approved_by);
create index chatter_attempts_owner on public.evzon_chatter_attempts(chatter_id,created_at desc);
create index chatter_time_owner on public.evzon_chatter_time(chatter_id,clock_in desc);
create index chatter_time_reviewer on public.evzon_chatter_time(reviewed_by);
create index chatter_payouts_owner on public.evzon_chatter_payouts(chatter_id,period desc);
create index chatter_payouts_creator on public.evzon_chatter_payouts(created_by);
create index chatter_announcements_creator on public.evzon_chatter_announcements(created_by);
alter table evzon_private.chatter_config enable row level security;
alter table evzon_private.chatter_answers enable row level security;
alter table evzon_private.chatter_passwords enable row level security;
revoke all on evzon_private.chatter_config,evzon_private.chatter_answers,evzon_private.chatter_passwords from public,anon,authenticated;
create function evzon_private.is_chatter() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.evzon_profiles where id=auth.uid() and role='CHATTER' and status='Approved');$$;
revoke all on function evzon_private.is_chatter() from public,anon;
grant execute on function evzon_private.is_chatter() to authenticated;
do $$declare t text;begin
 foreach t in array array['evzon_chatter_accounts','evzon_chatter_lessons','evzon_chatter_progress','evzon_chatter_attempts','evzon_chatter_time','evzon_chatter_payouts','evzon_chatter_announcements'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['evzon_chatter_progress','evzon_chatter_attempts','evzon_chatter_time','evzon_chatter_payouts'] loop
 execute format('create policy chatter_own_read on public.%I for select to authenticated using ((select evzon_private.is_admin()) or (chatter_id=(select auth.uid()) and (select evzon_private.is_chatter())))',t);
 end loop;
end $$;
create policy chatter_account_read on public.evzon_chatter_accounts for select to authenticated using((select evzon_private.is_admin()) or (id=(select auth.uid()) and (select evzon_private.is_chatter())));
create policy chatter_lesson_read on public.evzon_chatter_lessons for select to authenticated using((select evzon_private.is_admin()) or (published and (select evzon_private.is_chatter()) and exists(select 1 from public.evzon_chatter_accounts a where a.id=(select auth.uid()) and a.completed_at is null)));
create policy chatter_announcement_read on public.evzon_chatter_announcements for select to authenticated using((select evzon_private.is_admin()) or (published and (select evzon_private.is_chatter())));
-- Trusted app metadata is only set by the authenticated admin provisioning function.
create or replace function evzon_private.profile_created() returns trigger language plpgsql security definer set search_path='' as $$
declare w jsonb;begin
 insert into public.evzon_profiles(id,name,email) values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''),split_part(new.email,'@',1),'Referrer'),100),coalesce(new.email,'')) on conflict(id) do update set email=excluded.email;
 if TG_OP='INSERT' and new.raw_app_meta_data->>'evzon_role'='CHATTER' then
  perform pg_advisory_xact_lock(782541);
  if not exists(select 1 from public.evzon_profiles where id=(new.raw_app_meta_data->>'created_by')::uuid and role='ADMIN' and status='Approved') then raise exception 'EVZON_FORBIDDEN'; end if;
  select x into w from public.evzon_workspace,jsonb_array_elements(state->'workers') x where x->>'id'=new.raw_app_meta_data->>'worker_id';
  if w is null or w->>'status'<>'Training' then raise exception 'EVZON_INVALID: Select a worker with Training status'; end if;
  update public.evzon_profiles set role='CHATTER',status='Approved' where id=new.id;
  insert into public.evzon_chatter_accounts(id,worker_id,training_start,created_by) values(new.id,w->>'id',(new.raw_app_meta_data->>'training_start')::date,(new.raw_app_meta_data->>'created_by')::uuid);
  insert into evzon_private.chatter_passwords values(new.id,new.encrypted_password);
 elsif new.email_confirmed_at is not null and exists(select 1 from evzon_private.admin_bootstrap where email=lower(new.email)) then
  update public.evzon_profiles set role='ADMIN',status='Approved' where id=new.id;
  delete from evzon_private.admin_bootstrap where email=lower(new.email);
 end if;
 return new;
end $$;
-- Existing referral endpoints cannot be used by chatter accounts.
create or replace function public.evzon_portal() returns jsonb language plpgsql security invoker set search_path='' as $$begin
 if not exists(select 1 from public.evzon_profiles where id=auth.uid() and role in ('ADMIN','REFERRER')) then raise exception 'EVZON_FORBIDDEN';end if;
 return evzon_private.portal();end $$;
create or replace function public.evzon_command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$begin
 if not exists(select 1 from public.evzon_profiles where id=auth.uid() and role in ('ADMIN','REFERRER')) then raise exception 'EVZON_FORBIDDEN';end if;
 if p_action='account' and exists(select 1 from public.evzon_profiles where id=(p_data->>'id')::uuid and role='CHATTER') then raise exception 'EVZON_INVALID: Manage chatter access from Chatter management';end if;
 return evzon_private.command(p_action,p_data);end $$;
drop policy config_read on public.evzon_referral_config;
create policy config_read on public.evzon_referral_config for select to authenticated using(exists(select 1 from public.evzon_profiles where id=(select auth.uid()) and role in ('ADMIN','REFERRER')));
create function evzon_private.chatter_portal() returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.evzon_profiles; admin boolean; a public.evzon_chatter_accounts; s jsonb; w jsonb; cfg jsonb;begin
 select * into me from public.evzon_profiles where id=auth.uid();
 admin:=evzon_private.is_admin();
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 select * into a from public.evzon_chatter_accounts where id=me.id;
 select state into s from public.evzon_workspace where id;
 select x into w from jsonb_array_elements(s->'workers') x where x->>'id'=a.worker_id;
 select to_jsonb(c)-'id' into cfg from evzon_private.chatter_config c where id;
 if not admin then
  cfg:=jsonb_set(cfg,'{questions}',case when a.completed_at is null and (now() at time zone 'Europe/Skopje')::date>=a.training_start+4 and (select count(*) from public.evzon_chatter_progress where chatter_id=me.id and day<5 and status='Approved')=4 and (cfg->>'exam_enabled')::boolean then (select coalesce(jsonb_agg(q-'correct'),'[]') from jsonb_array_elements(cfg->'questions') q) else '[]'::jsonb end);
 end if;
 return jsonb_build_object('profile',to_jsonb(me),'server_time',now(),'today',(now() at time zone 'Europe/Skopje')::date,
 'accounts',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('name',p.name,'email',p.email,'status',p.status) order by c.created_at desc),'[]') from public.evzon_chatter_accounts c join public.evzon_profiles p on p.id=c.id where admin or c.id=me.id),
 'lessons',(select coalesce(jsonb_agg(case when admin or published then to_jsonb(l) else to_jsonb(l)||jsonb_build_object('content','','content_mk','') end order by day),'[]') from public.evzon_chatter_lessons l where admin or a.completed_at is null),
 'progress',(select coalesce(jsonb_agg(to_jsonb(p) order by p.day),'[]') from public.evzon_chatter_progress p where admin or p.chatter_id=me.id),
 'config',cfg,'attempts',(select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]') from (select * from public.evzon_chatter_attempts where admin or chatter_id=me.id order by created_at desc limit 1000) p),
 'entries',(select coalesce(jsonb_agg(to_jsonb(p) order by p.clock_in desc),'[]') from (select * from public.evzon_chatter_time where admin or chatter_id=me.id order by clock_in desc limit 2000) p),
 'payouts',(select coalesce(jsonb_agg(to_jsonb(p) order by p.period desc,p.created_at desc),'[]') from (select * from public.evzon_chatter_payouts where admin or chatter_id=me.id order by period desc,created_at desc limit 2000) p),
 'announcements',(select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]') from (select * from public.evzon_chatter_announcements where admin or published order by created_at desc limit 100) p),
 'worker',case when w is null then null else jsonb_build_object('id',w->'id','name',w->'name','status',w->'status','salary',w->'salary','bonus',w->'bonus','payroll',w->'payroll','wageRate',w->'wageRate','overtimeRate',w->'overtimeRate','availability',w->'availability','shift',w->'shift') end,
 'shifts',(select coalesce(jsonb_agg(jsonb_build_object('id',x->'id','date',x->'date','start',x->'start','scheduled',x->'scheduled','actual',x->'actual','overtime',x->'overtime','approved',x->'approved','absence',x->'absence') order by x->>'date',x->>'start'),'[]') from jsonb_array_elements(s->'shifts') x where coalesce(nullif(x->>'replacement',''),x->>'worker')=a.worker_id and (x->>'date')::date between (now() at time zone 'Europe/Skopje')::date-31 and (now() at time zone 'Europe/Skopje')::date+90));
end $$;
create function evzon_private.chatter_command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.evzon_profiles; admin boolean; a public.evzon_chatter_accounts; d int; localday date:=(now() at time zone 'Europe/Skopje')::date; cfg evzon_private.chatter_config; q jsonb; score numeric; correct_count int:=0; attempt_id uuid; v_id uuid; s jsonb; w jsonb; sh jsonb; entry public.evzon_chatter_time; pay public.evzon_chatter_payouts; changed boolean:=false; hours numeric; regular numeric; overtime numeric; feedback text;begin
 select * into me from public.evzon_profiles where id=auth.uid();admin:=evzon_private.is_admin();
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>150000 then raise exception 'EVZON_INVALID: Invalid request';end if;
 perform pg_advisory_xact_lock(782541);
 select state into s from public.evzon_workspace where id for update;
 select * into a from public.evzon_chatter_accounts where id=case when admin then nullif(p_data->>'chatter_id','')::uuid else me.id end for update;
 if not admin and a.id is null then raise exception 'EVZON_FORBIDDEN';end if;
 if not admin and a.must_change_password and p_action<>'password-set' then raise exception 'EVZON_INVALID: Change your temporary password first';end if;
 if p_action='password-set' then
  if admin then raise exception 'EVZON_FORBIDDEN';end if;
  if exists(select 1 from evzon_private.chatter_passwords p join auth.users u on u.id=p.id where p.id=me.id and p.initial_hash=u.encrypted_password) then raise exception 'EVZON_INVALID: Choose a different password';end if;
  delete from evzon_private.chatter_passwords where id=me.id;
  update public.evzon_chatter_accounts set must_change_password=false where id=me.id;
 elsif p_action='submit-day' then
  if admin then raise exception 'EVZON_FORBIDDEN';end if;
  d:=(p_data->>'day')::int;
  if d is null or d not between 1 and 7 or a.completed_at is not null or localday<a.training_start+d-1 then raise exception 'EVZON_INVALID: This training day is not available';end if;
  if (select count(*) from public.evzon_chatter_progress where chatter_id=a.id and day<d and status='Approved')<>d-1 then raise exception 'EVZON_INVALID: Complete previous days first';end if;
  if not exists(select 1 from public.evzon_chatter_lessons where day=d and published and length(trim(content))>0) then raise exception 'EVZON_INVALID: Your trainer has not published this lesson yet';end if;
  if d>=5 and a.hired_at is null then raise exception 'EVZON_INVALID: Pass the day 5 exam first';end if;
  if exists(select 1 from public.evzon_chatter_progress where chatter_id=a.id and day=d and status='Approved') then raise exception 'EVZON_INVALID: This day is already approved';end if;
  insert into public.evzon_chatter_progress(chatter_id,day,status,submitted_at) values(a.id,d,'Submitted',now()) on conflict(chatter_id,day) do update set status='Submitted',submitted_at=now();
 elsif p_action='exam' then
  if admin then raise exception 'EVZON_FORBIDDEN';end if;
  select * into cfg from evzon_private.chatter_config where id;
  if not cfg.exam_enabled or jsonb_array_length(cfg.questions)=0 then raise exception 'EVZON_INVALID: Your trainer has not published the exam yet';end if;
  if a.hired_at is not null or a.completed_at is not null then raise exception 'EVZON_INVALID: Your exam is already passed';end if;
  if localday<a.training_start+4 or (select count(*) from public.evzon_chatter_progress where chatter_id=a.id and day<5 and status='Approved')<>4 then raise exception 'EVZON_INVALID: Complete days 1–4 before the exam';end if;
  if (select count(*) from public.evzon_chatter_attempts where chatter_id=a.id)>=cfg.max_attempts then raise exception 'EVZON_INVALID: Attempt limit reached. Contact your trainer';end if;
  if jsonb_typeof(p_data->'answers') is distinct from 'object' then raise exception 'EVZON_INVALID: Answer every question';end if;
  for q in select * from jsonb_array_elements(cfg.questions) loop
   if (p_data->'answers'->>(q->>'id')) is null or (p_data->'answers'->>(q->>'id'))!~'^[0-3]$' then raise exception 'EVZON_INVALID: Answer every question';end if;
   if (p_data->'answers'->>(q->>'id'))::int=(q->>'correct')::int then correct_count:=correct_count+1;end if;
  end loop;
  score:=round(100.0*correct_count/jsonb_array_length(cfg.questions),2);
  insert into public.evzon_chatter_attempts(chatter_id,score,passed) values(a.id,score,score>=cfg.pass_score) returning id into attempt_id;
  insert into evzon_private.chatter_answers values(attempt_id,cfg.questions,p_data->'answers');
  if score>=cfg.pass_score then
   update public.evzon_chatter_accounts set hired_at=now() where id=a.id;
   update public.evzon_referrals set assessment_passed=true,hired_on=localday,stage='Hired',updated_at=now() where worker_id=a.worker_id and stage not in ('Rejected','Withdrawn');
  end if;
 elsif p_action='clock-in' then
  if admin or a.completed_at is null then raise exception 'EVZON_INVALID: Complete training before clocking in';end if;
  select x into w from jsonb_array_elements(s->'workers') x where x->>'id'=a.worker_id;
  if w is null or w->>'status'<>'Active' then raise exception 'EVZON_INVALID: Your worker record must be active';end if;
  if exists(select 1 from public.evzon_chatter_time where chatter_id=a.id and clock_out is null) then raise exception 'EVZON_INVALID: You are already clocked in';end if;
  if nullif(p_data->>'shift_id','') is not null then
   select x into sh from jsonb_array_elements(s->'shifts') x where x->>'id'=p_data->>'shift_id' and coalesce(nullif(x->>'replacement',''),x->>'worker')=a.worker_id;
   if sh is null or (sh->>'approved')::boolean or ((sh->>'absence')::boolean and coalesce(sh->>'replacement','')='') or (sh->>'date')::date not between localday-1 and localday then raise exception 'EVZON_INVALID: Select an assigned current shift';end if;
  end if;
  insert into public.evzon_chatter_time(chatter_id,shift_id) values(a.id,nullif(p_data->>'shift_id',''));
 elsif p_action='clock-out' then
  if admin then raise exception 'EVZON_FORBIDDEN';end if;
  update public.evzon_chatter_time set clock_out=now() where chatter_id=a.id and clock_out is null;
  if not found then raise exception 'EVZON_INVALID: You are not clocked in';end if;
 elsif admin then
  if p_action='account' then
   if a.id is null or p_data->>'status' not in ('Approved','Suspended') then raise exception 'EVZON_INVALID: Select a chatter account';end if;
   update public.evzon_profiles set status=p_data->>'status' where id=a.id and role='CHATTER';
   if p_data->>'status'='Suspended' then update public.evzon_chatter_time set clock_out=now(),notes='Account suspended; attendance requires review.' where chatter_id=a.id and clock_out is null;end if;
  elsif p_action='lesson' then
   d:=(p_data->>'day')::int;
   if d is null or d not between 1 and 7 or length(trim(coalesce(p_data->>'title',''))) not between 1 and 160 or ((p_data->>'published')::boolean and length(trim(coalesce(p_data->>'content','')))=0) then raise exception 'EVZON_INVALID: A published lesson needs a title and content';end if;
   update public.evzon_chatter_lessons set title=trim(p_data->>'title'),title_mk=coalesce(p_data->>'title_mk',''),content=coalesce(p_data->>'content',''),content_mk=coalesce(p_data->>'content_mk',''),published=coalesce((p_data->>'published')::boolean,false) where day=d;
  elsif p_action='exam-config' then
   if jsonb_typeof(p_data->'questions') is distinct from 'array' or jsonb_array_length(p_data->'questions')>60 then raise exception 'EVZON_INVALID: Add up to 60 questions';end if;
   if (p_data->>'exam_enabled')::boolean and jsonb_array_length(p_data->'questions')=0 then raise exception 'EVZON_INVALID: Add questions before publishing';end if;
   for q in select * from jsonb_array_elements(p_data->'questions') loop
    if coalesce(q->>'id','')='' or length(trim(coalesce(q->>'question',''))) not between 1 and 2000 or jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options')<>4 or coalesce(q->>'correct','')!~'^[0-3]$' then raise exception 'EVZON_INVALID: Each question needs four answers and one correct choice';end if;
    if exists(select 1 from jsonb_array_elements_text(q->'options') x where length(trim(x)) not between 1 and 1000) then raise exception 'EVZON_INVALID: Fill in every answer option';end if;
   end loop;
   if (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(p_data->'questions') x) then raise exception 'EVZON_INVALID: Duplicate question IDs';end if;
   if coalesce(p_data->>'discord_url','')<>'' and p_data->>'discord_url'!~'^https://(discord\.gg/|discord\.com/)' then raise exception 'EVZON_INVALID: Use a Discord invite or channel URL';end if;
   update evzon_private.chatter_config set pass_score=(p_data->>'pass_score')::int,max_attempts=(p_data->>'max_attempts')::int,exam_enabled=(p_data->>'exam_enabled')::boolean,questions=p_data->'questions',discord_url=coalesce(p_data->>'discord_url','') where id;
  elsif p_action='review-day' then
   d:=(p_data->>'day')::int;feedback:=trim(coalesce(p_data->>'feedback',''));
   if a.id is null or a.completed_at is not null or d is null or d not between 1 and 7 or p_data->>'status' not in ('Approved','Changes needed') then raise exception 'EVZON_INVALID: Select an unfinished training day';end if;
   if length(feedback)<3 then raise exception 'EVZON_INVALID: Add trainer feedback';end if;
   if not exists(select 1 from public.evzon_chatter_progress where chatter_id=a.id and day=d and status in ('Submitted','Changes needed')) then raise exception 'EVZON_INVALID: The chatter must submit this day first';end if;
   if p_data->>'status'='Approved' then
    if localday<a.training_start+d-1 or (select count(*) from public.evzon_chatter_progress where chatter_id=a.id and day<d and status='Approved')<>d-1 or (d>=5 and a.hired_at is null) then raise exception 'EVZON_INVALID: Previous days and the exam must be completed in order';end if;
    if d=7 and not coalesce((p_data->>'ceo_review')::boolean,false) then raise exception 'EVZON_INVALID: Confirm the Discord screen-share trial and CEO feedback';end if;
   end if;
   update public.evzon_chatter_progress set status=p_data->>'status',feedback=feedback,approved_at=case when p_data->>'status'='Approved' then now() else null end,approved_by=me.id where chatter_id=a.id and day=d;
   if d=7 and p_data->>'status'='Approved' then
    if not exists(select 1 from jsonb_array_elements(s->'workers') x where x->>'id'=a.worker_id and x->>'status'='Training') then raise exception 'EVZON_INVALID: The linked worker must have Training status';end if;
    update public.evzon_chatter_accounts set completed_at=now() where id=a.id;
    s:=jsonb_set(s,'{workers}',(select jsonb_agg(case when x->>'id'=a.worker_id then x||jsonb_build_object('status','Active','trainingComplete',true,'assessmentPassed',true,'start',localday) else x end) from jsonb_array_elements(s->'workers') x));changed:=true;
    update public.evzon_referrals set training_complete=true,assessment_passed=true,training_started_on=a.training_start,training_completed_on=localday,training_days_completed=7,hired_on=coalesce(hired_on,localday),worker_status='Active',stage='Active',updated_at=now() where worker_id=a.worker_id and stage not in ('Rejected','Withdrawn');
   end if;
  elsif p_action='attendance' then
   select * into entry from public.evzon_chatter_time where id=(p_data->>'id')::uuid for update;
   if entry.id is null or entry.status<>'Pending' then raise exception 'EVZON_INVALID: This entry is already reviewed or missing';end if;
   if entry.clock_out is null then raise exception 'EVZON_INVALID: The chatter must clock out before review';end if;
   if p_data->>'status' not in ('Approved','Rejected') then raise exception 'EVZON_INVALID: Select approval or rejection';end if;
   select * into a from public.evzon_chatter_accounts where id=entry.chatter_id;
   regular:=coalesce((p_data->>'regular_hours')::numeric,0);overtime:=coalesce((p_data->>'overtime_hours')::numeric,0);
   hours:=extract(epoch from entry.clock_out-entry.clock_in)/3600;
   if regular<0 or overtime<0 or regular+overtime>24 or regular+overtime>hours+0.02 or regular::text='NaN' or overtime::text='NaN' then raise exception 'EVZON_INVALID: Approved hours cannot exceed recorded hours or 24 hours';end if;
   if p_data->>'status'='Approved' then
    if regular+overtime<=0 then raise exception 'EVZON_INVALID: Enter approved working hours';end if;
    if entry.shift_id is not null then
     select x into sh from jsonb_array_elements(s->'shifts') x where x->>'id'=entry.shift_id;
     if sh is null or (sh->>'approved')::boolean or coalesce(nullif(sh->>'replacement',''),sh->>'worker')<>a.worker_id then raise exception 'EVZON_INVALID: The linked shift changed or was already approved. Review it in Schedule';end if;
     s:=jsonb_set(s,'{shifts}',(select jsonb_agg(case when x->>'id'=entry.shift_id then x||jsonb_build_object('actual',regular,'overtime',overtime,'approved',true,'absence',false,'attendanceId',entry.id) else x end) from jsonb_array_elements(s->'shifts') x));
    else
     entry.shift_id:='clock-'||entry.id;
     s:=jsonb_set(s,'{shifts}',coalesce(s->'shifts','[]')||jsonb_build_array(jsonb_build_object('id',entry.shift_id,'worker',a.worker_id,'agency','','date',(entry.clock_in at time zone 'Europe/Skopje')::date,'start',to_char(entry.clock_in at time zone 'Europe/Skopje','HH24:MI'),'scheduled',regular+overtime,'actual',regular,'overtime',overtime,'approved',true,'absence',false,'replacement','','notes',coalesce(p_data->>'notes',''),'attendanceId',entry.id)));
    end if;changed:=true;
   end if;
   update public.evzon_chatter_time set status=p_data->>'status',shift_id=entry.shift_id,regular_hours=case when p_data->>'status'='Approved' then regular else 0 end,overtime_hours=case when p_data->>'status'='Approved' then overtime else 0 end,notes=coalesce(p_data->>'notes',''),reviewed_by=me.id where id=entry.id;
  elsif p_action='payout-create' then
   if a.id is null then raise exception 'EVZON_INVALID: Select a chatter';end if;
   insert into public.evzon_chatter_payouts(chatter_id,period,amount,notes,created_by) values(a.id,(p_data->>'period')::date,(p_data->>'amount')::numeric,coalesce(p_data->>'notes',''),me.id);
  elsif p_action='payout-update' then
   select * into pay from public.evzon_chatter_payouts where id=(p_data->>'id')::uuid for update;
   if pay.id is null or pay.status<>'Approved' or p_data->>'status' not in ('Paid','Cancelled') then raise exception 'EVZON_INVALID: This payout is already settled or missing';end if;
   if p_data->>'status'='Paid' then
    if length(trim(coalesce(p_data->>'reference','')))<3 then raise exception 'EVZON_INVALID: Record a payment reference';end if;
    select * into a from public.evzon_chatter_accounts where id=pay.chatter_id;
    s:=jsonb_set(s,'{actualExpenses}',coalesce(s->'actualExpenses','[]')||jsonb_build_array(jsonb_build_object('id','chatter-payout-'||pay.id,'name','Chatter payroll','category','Worker salary','kind','Worker','team','','agency','','worker',a.worker_id,'date',localday,'amount',pay.amount,'notes','Payment reference: '||(p_data->>'reference'),'chatterPayoutId',pay.id)));
    changed:=true;
   end if;
   update public.evzon_chatter_payouts set status=p_data->>'status',paid_at=case when p_data->>'status'='Paid' then now() else null end,reference=coalesce(p_data->>'reference','') where id=pay.id;
  elsif p_action='announcement' then
   if nullif(p_data->>'id','') is null then insert into public.evzon_chatter_announcements(title,body,published,created_by) values(trim(p_data->>'title'),trim(p_data->>'body'),coalesce((p_data->>'published')::boolean,true),me.id);
   else update public.evzon_chatter_announcements set title=trim(p_data->>'title'),body=trim(p_data->>'body'),published=(p_data->>'published')::boolean where id=(p_data->>'id')::uuid;end if;
  else raise exception 'EVZON_INVALID: Unknown chatter action';end if;
 else raise exception 'EVZON_FORBIDDEN';end if;
 if changed then
  perform evzon_private.validate_workspace(s);
  update public.evzon_workspace set state=s,revision=revision+1,updated_at=now(),updated_by=me.id where id;
  perform evzon_private.refresh_rewards();
 end if;
 perform evzon_private.audit('Chatter: '||p_action,null,p_data-'answers');
 return evzon_private.chatter_portal();
end $$;
revoke all on function evzon_private.chatter_portal(),evzon_private.chatter_command(text,jsonb) from public,anon;
grant execute on function evzon_private.chatter_portal(),evzon_private.chatter_command(text,jsonb) to authenticated;
create function public.evzon_chatter_portal() returns jsonb language sql security invoker set search_path='' as $$select evzon_private.chatter_portal();$$;
create function public.evzon_chatter_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select evzon_private.chatter_command(p_action,p_data);$$;
revoke all on function public.evzon_chatter_portal(),public.evzon_chatter_command(text,jsonb) from public,anon;
grant execute on function public.evzon_chatter_portal(),public.evzon_chatter_command(text,jsonb) to authenticated;
;
