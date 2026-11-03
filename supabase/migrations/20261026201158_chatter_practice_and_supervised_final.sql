-- Practice completion is independent of score. Final starts require a one-use admin grant.
create table evzon_private.exam_settings (
 id boolean primary key default true check(id),
 pass_score integer not null default 80 check(pass_score between 1 and 100)
);
insert into evzon_private.exam_settings(id) values(true);
create table evzon_private.exam_questions (
 id text primary key,
 test_key text not null check(test_key in ('practice-1','practice-2','practice-3','practice-4','practice-5','final')),
 unit_id text not null references evzon_private.training_units(id),
 prompt jsonb not null, options jsonb not null check(jsonb_array_length(options)=4),
 correct text not null check(correct in ('a','b','c','d')),
 source_anchor text not null, explanation jsonb not null,
 check(length(prompt->>'en')>0 and length(prompt->>'mk')>0)
);
create index exam_questions_test on evzon_private.exam_questions(test_key);
create index exam_questions_unit on evzon_private.exam_questions(unit_id);
create table evzon_private.exam_permissions (
 id uuid primary key default gen_random_uuid(),
 chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,
 granted_by uuid not null references public.evzon_profiles(id),
 granted_at timestamptz not null default now(), used_at timestamptz, revoked_at timestamptz,
 note text not null default '' check(length(note)<=4000)
);
create unique index exam_one_unused_permission on evzon_private.exam_permissions(chatter_id) where used_at is null and revoked_at is null;
create index exam_permissions_granter on evzon_private.exam_permissions(granted_by);
create table evzon_private.exam_attempts (
 id uuid primary key default gen_random_uuid(),
 chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,
 test_key text not null check(test_key in ('practice-1','practice-2','practice-3','practice-4','practice-5','final')),
 status text not null default 'In progress' check(status in ('In progress','Submitted')),
 questions jsonb not null, question_order text not null, answers jsonb not null default '{}',
 version integer not null default 0,
 total integer not null check(total in (25,30)), correct_count integer,
 score numeric(5,2), passed boolean, pass_score integer not null check(pass_score between 1 and 100),
 permission_id uuid unique references evzon_private.exam_permissions(id),
 started_at timestamptz not null default now(), submitted_at timestamptz,
 feedback text not null default '' check(length(feedback)<=4000), reviewed_by uuid references public.evzon_profiles(id), reviewed_at timestamptz,
 check((test_key='final' and permission_id is not null and total=30) or (test_key<>'final' and permission_id is null and total=25)),
 check((status='In progress' and submitted_at is null and score is null and correct_count is null and passed is null) or (status='Submitted' and submitted_at is not null and score is not null and correct_count between 0 and total and ((test_key='final' and passed is not null) or (test_key<>'final' and passed is null))))
);
create unique index exam_one_running on evzon_private.exam_attempts(chatter_id) where status='In progress';
create unique index exam_unique_question_sequence on evzon_private.exam_attempts(chatter_id,test_key,question_order);
create index exam_attempts_history on evzon_private.exam_attempts(chatter_id,submitted_at desc);
create index exam_attempts_reviewer on evzon_private.exam_attempts(reviewed_by);
alter table evzon_private.exam_settings enable row level security;
alter table evzon_private.exam_questions enable row level security;
alter table evzon_private.exam_permissions enable row level security;
alter table evzon_private.exam_attempts enable row level security;
revoke all on evzon_private.exam_settings,evzon_private.exam_questions,evzon_private.exam_permissions,evzon_private.exam_attempts from public,anon,authenticated;

create function evzon_private.exam_ready(p_chatter uuid) returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.evzon_chatter_accounts a join public.evzon_profiles p on p.id=a.id where a.id=p_chatter and p.role='CHATTER' and p.status='Approved' and not a.must_change_password and a.completed_at is null and (now() at time zone 'Europe/Skopje')::date>=a.training_start)
 and exists(select 1 from public.evzon_chatter_lessons where day=5 and published)
 and (select count(*) from public.evzon_chatter_progress where chatter_id=p_chatter and day<5 and status='Approved')=4;
$$;
create function evzon_private.exam_completed_practices(p_chatter uuid) returns integer language sql stable security invoker set search_path='' as $$
 select count(distinct test_key)::integer from evzon_private.exam_attempts where chatter_id=p_chatter and test_key<>'final' and status='Submitted';
$$;
create function evzon_private.exam_summary(p_chatter uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('chatter_id',a.id,'name',p.name,'status',p.status,'unlocked',evzon_private.exam_ready(a.id),'graduated',a.completed_at is not null,
 'practice_completed',(select coalesce(jsonb_agg(k order by k),'[]') from (select distinct test_key k from evzon_private.exam_attempts where chatter_id=a.id and test_key<>'final' and status='Submitted') t),
 'final_passed',a.hired_at is not null or exists(select 1 from evzon_private.exam_attempts where chatter_id=a.id and test_key='final' and passed),
 'permission',(select to_jsonb(g) from evzon_private.exam_permissions g where g.chatter_id=a.id and g.used_at is null and g.revoked_at is null),
 'active_attempt',(select id from evzon_private.exam_attempts where chatter_id=a.id and status='In progress'))
 from public.evzon_chatter_accounts a join public.evzon_profiles p on p.id=a.id where a.id=p_chatter;
$$;
create function evzon_private.exam_attempt_json(p_attempt uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select (to_jsonb(a)-'question_order'-'questions') || jsonb_build_object('questions',
 (select coalesce(jsonb_agg(case when a.status='Submitted' then q else q-'correct'-'explanation'-'source_anchor'-'source_title'-'source_title_mk'-'source_day'-'unit_id' end order by pos),'[]') from jsonb_array_elements(a.questions) with ordinality t(q,pos)))
 from evzon_private.exam_attempts a where a.id=p_attempt;
$$;
create function evzon_private.exams_portal(p_attempt uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin(); a public.evzon_chatter_accounts; v_attempt uuid; result jsonb;begin
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 if not admin then
  select * into a from public.evzon_chatter_accounts where id=auth.uid();
  if a.id is null or a.must_change_password then raise exception 'EVZON_FORBIDDEN';end if;
  if a.completed_at is not null then return jsonb_build_object('admin',false,'summaries','[]'::jsonb,'attempts','[]'::jsonb,'attempt',null,'bank','[]'::jsonb,'settings',jsonb_build_object('pass_score',80),'discord_url','');end if;
 end if;
 v_attempt:=p_attempt;
 if v_attempt is null and not admin then select id into v_attempt from evzon_private.exam_attempts where chatter_id=auth.uid() and status='In progress';end if;
 if v_attempt is not null and not exists(select 1 from evzon_private.exam_attempts where id=v_attempt and (admin or chatter_id=auth.uid())) then raise exception 'EVZON_FORBIDDEN';end if;
 result:=jsonb_build_object('admin',admin,'settings',(select to_jsonb(c)-'id' from evzon_private.exam_settings c where id),
 'discord_url',(select discord_url from evzon_private.chatter_config where id),
 'summaries',(select coalesce(jsonb_agg(evzon_private.exam_summary(c.id) order by c.created_at desc),'[]') from public.evzon_chatter_accounts c where admin or c.id=auth.uid()),
 'attempts',(select coalesce(jsonb_agg(to_jsonb(t) order by t.started_at desc),'[]') from (select id,chatter_id,test_key,status,version,total,correct_count,score,passed,pass_score,started_at,submitted_at,feedback,reviewed_at from evzon_private.exam_attempts where admin or chatter_id=auth.uid() order by started_at desc limit 1000) t),
 'attempt',case when v_attempt is null then null else evzon_private.exam_attempt_json(v_attempt) end,
 'bank',case when admin then (select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('source_title',u.title,'source_title_mk',u.title_mk,'source_day',u.day) order by q.test_key,q.id),'[]') from evzon_private.exam_questions q join evzon_private.training_units u on u.id=q.unit_id) else '[]'::jsonb end);
 return result;
end $$;

create function evzon_private.exams_command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin(); who uuid; a public.evzon_chatter_accounts; g evzon_private.exam_permissions; attempt evzon_private.exam_attempts; q jsonb; opt jsonb; k text; val jsonb; bank jsonb; sequence text; tries integer:=0; total_count integer; right_count integer:=0; threshold integer; key text; permission uuid; note text;begin
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>30000 then raise exception 'EVZON_INVALID: Invalid exam request';end if;
 -- Serialize start, submit, authorization and existing training changes together.
 perform pg_advisory_xact_lock(782541);
 who:=case when admin then nullif(p_data->>'chatter_id','')::uuid else auth.uid() end;
 select * into a from public.evzon_chatter_accounts where id=who for update;
 if not admin and (a.id is null or a.must_change_password or a.completed_at is not null) then raise exception 'EVZON_FORBIDDEN';end if;
 if p_action in ('authorize','revoke','settings','feedback') then
  if not admin then raise exception 'EVZON_FORBIDDEN';end if;
  if p_action='settings' then
   if coalesce(p_data->>'pass_score','')!~'^[0-9]{1,3}$' or (p_data->>'pass_score')::int not between 1 and 100 then raise exception 'EVZON_INVALID: Use a passing score from 1 to 100';end if;
   if coalesce(p_data->>'discord_url','')<>'' and (p_data->>'discord_url'!~'^https://(discord\.gg/|discord\.com/)' or length(p_data->>'discord_url')>500) then raise exception 'EVZON_INVALID: Use a Discord invite or channel URL';end if;
   update evzon_private.exam_settings set pass_score=(p_data->>'pass_score')::int where id;
   update evzon_private.chatter_config set discord_url=coalesce(p_data->>'discord_url','') where id;
  elsif p_action='authorize' then
   if a.id is null or not evzon_private.exam_ready(who) or evzon_private.exam_completed_practices(who)<>5 then raise exception 'EVZON_INVALID: Finish all five practice tests before final authorization';end if;
   if a.hired_at is not null or exists(select 1 from evzon_private.exam_attempts where chatter_id=who and test_key='final' and passed) then raise exception 'EVZON_INVALID: Final exam already passed';end if;
   if exists(select 1 from evzon_private.exam_attempts where chatter_id=who and status='In progress') then raise exception 'EVZON_INVALID: Finish the current test first';end if;
   if exists(select 1 from evzon_private.exam_permissions where chatter_id=who and used_at is null and revoked_at is null) then raise exception 'EVZON_INVALID: Final exam permission already granted';end if;
   note:=trim(coalesce(p_data->>'note',''));
   insert into evzon_private.exam_permissions(chatter_id,granted_by,note) values(who,auth.uid(),note);
  elsif p_action='revoke' then
   update evzon_private.exam_permissions set revoked_at=now() where chatter_id=who and used_at is null and revoked_at is null;
   if not found then raise exception 'EVZON_INVALID: No unused final exam permission';end if;
  else
   if length(trim(coalesce(p_data->>'feedback',''))) not between 1 and 4000 then raise exception 'EVZON_INVALID: Add 1–4,000 characters of feedback';end if;
   update evzon_private.exam_attempts set feedback=trim(p_data->>'feedback'),reviewed_by=auth.uid(),reviewed_at=now() where id=(p_data->>'id')::uuid and status='Submitted' returning * into attempt;
   if not found then raise exception 'EVZON_INVALID: Select a submitted test';end if;
  end if;
  perform evzon_private.audit('Exams: '||p_action,null,p_data);
  return evzon_private.exams_portal(attempt.id);
 end if;
 if admin then raise exception 'EVZON_FORBIDDEN';end if;
 if not evzon_private.exam_ready(who) then raise exception 'EVZON_INVALID: Complete learning materials 1–4 and receive trainer approval first';end if;
 if p_action='start' then
  key:=p_data->>'test_key';
  if key is null or key not in ('practice-1','practice-2','practice-3','practice-4','practice-5','final') then raise exception 'EVZON_INVALID: Select a test';end if;
  select * into attempt from evzon_private.exam_attempts where chatter_id=who and status='In progress' for update;
  if attempt.id is not null then
   if attempt.test_key<>key then raise exception 'EVZON_INVALID: Finish your current test before starting another';end if;
   return evzon_private.exams_portal(attempt.id);
  end if;
  if key='final' then
   if evzon_private.exam_completed_practices(who)<>5 then raise exception 'EVZON_INVALID: Finish all five practice tests first; scores do not affect eligibility';end if;
   if a.hired_at is not null then raise exception 'EVZON_INVALID: Final exam already passed';end if;
   select * into g from evzon_private.exam_permissions where chatter_id=who and used_at is null and revoked_at is null for update;
   if g.id is null then raise exception 'EVZON_INVALID: Your administrator must authorize this final exam attempt';end if;
   if coalesce((p_data->>'screenshare_confirmed')::boolean,false)=false then raise exception 'EVZON_INVALID: Confirm your screen-share session with the CEO';end if;
   permission:=g.id;
  end if;
  select pass_score into threshold from evzon_private.exam_settings where id;
  total_count:=case when key='final' then 30 else 25 end;
  if (select count(*) from evzon_private.exam_questions where test_key=key)<>total_count then raise exception 'EVZON_INVALID: This test is not ready; contact your trainer';end if;
  if exists(select 1 from evzon_private.exam_questions q join evzon_private.training_units u on u.id=q.unit_id where q.test_key=key and (not u.published or strpos(u.body,q.source_anchor)=0)) then raise exception 'EVZON_INVALID: A source guide changed; your trainer must review this test';end if;
  loop
   select jsonb_agg(to_jsonb(q)||jsonb_build_object('options',(select jsonb_agg(o order by random()) from jsonb_array_elements(q.options) o),'source_title',u.title,'source_title_mk',u.title_mk,'source_day',u.day) order by random()) into bank from evzon_private.exam_questions q join evzon_private.training_units u on u.id=q.unit_id where q.test_key=key;
   select string_agg(q->>'id',',' order by pos) into sequence from jsonb_array_elements(bank) with ordinality v(q,pos);
   exit when not exists(select 1 from evzon_private.exam_attempts where chatter_id=who and test_key=key and question_order=sequence);
   tries:=tries+1;if tries>10 then raise exception 'EVZON_INVALID: Could not create a fresh question order; retry';end if;
  end loop;
  insert into evzon_private.exam_attempts(chatter_id,test_key,questions,question_order,total,pass_score,permission_id) values(who,key,bank,sequence,total_count,threshold,permission) returning * into attempt;
  if permission is not null then update evzon_private.exam_permissions set used_at=now() where id=permission;end if;
  perform evzon_private.audit('Exams: started',null,jsonb_build_object('id',attempt.id,'test',key,'chatter_id',who));
 elsif p_action in ('save','submit') then
  select * into attempt from evzon_private.exam_attempts where id=(p_data->>'id')::uuid and chatter_id=who for update;
  if attempt.id is null then raise exception 'EVZON_FORBIDDEN';end if;
  -- A retried submit is idempotent after a lost response.
  if attempt.status='Submitted' and p_action='submit' then return evzon_private.exams_portal(attempt.id);end if;
  if attempt.status<>'In progress' then raise exception 'EVZON_INVALID: This test is already submitted';end if;
  if coalesce(p_data->>'version','')!~'^[0-9]+$' or (p_data->>'version')::integer<>attempt.version then raise exception 'EVZON_INVALID: This attempt changed in another tab. Refresh before continuing';end if;
  if jsonb_typeof(p_data->'answers') is distinct from 'object' then raise exception 'EVZON_INVALID: Invalid answers';end if;
  for k,val in select * from jsonb_each(p_data->'answers') loop
   select v into q from jsonb_array_elements(attempt.questions) v where v->>'id'=k;
   if q is null or jsonb_typeof(val)<>'string' or not exists(select 1 from jsonb_array_elements(q->'options') o where o->>'id'=val#>>'{}') then raise exception 'EVZON_INVALID: Invalid question or answer';end if;
  end loop;
  if p_action='submit' then
   if (select count(*) from jsonb_object_keys(p_data->'answers'))<>attempt.total then raise exception 'EVZON_INVALID: Answer every question before submitting';end if;
   for q in select * from jsonb_array_elements(attempt.questions) loop
    if p_data->'answers'->>(q->>'id')=q->>'correct' then right_count:=right_count+1;end if;
   end loop;
   update evzon_private.exam_attempts set answers=p_data->'answers',version=version+1,status='Submitted',submitted_at=now(),correct_count=right_count,score=round(right_count*100.0/total,2),passed=case when test_key='final' then right_count*100>=total*pass_score else null end where id=attempt.id returning * into attempt;
   if attempt.test_key='final' and attempt.passed then
    update public.evzon_chatter_accounts set hired_at=coalesce(hired_at,now()) where id=who;
    update public.evzon_referrals set assessment_passed=true,hired_on=(now() at time zone 'Europe/Skopje')::date,stage='Hired',updated_at=now() where worker_id=a.worker_id and stage not in ('Rejected','Withdrawn');
   end if;
   perform evzon_private.audit('Exams: submitted',null,jsonb_build_object('id',attempt.id,'chatter_id',who,'test',attempt.test_key,'correct',right_count,'total',attempt.total,'score',attempt.score,'passed',attempt.passed));
  else
   update evzon_private.exam_attempts set answers=p_data->'answers',version=version+1 where id=attempt.id returning * into attempt;
  end if;
 else raise exception 'EVZON_INVALID: Unknown exam action';end if;
 return evzon_private.exams_portal(attempt.id);
end $$;
revoke all on function evzon_private.exam_ready(uuid),evzon_private.exam_completed_practices(uuid),evzon_private.exam_summary(uuid),evzon_private.exam_attempt_json(uuid),evzon_private.exams_portal(uuid),evzon_private.exams_command(text,jsonb) from public,anon,authenticated;
grant execute on function evzon_private.exams_portal(uuid),evzon_private.exams_command(text,jsonb) to authenticated;
create function public.evzon_exams_portal(p_attempt uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select evzon_private.exams_portal(p_attempt); $$;
create function public.evzon_exams_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select evzon_private.exams_command(p_action,p_data); $$;
revoke all on function public.evzon_exams_portal(uuid),public.evzon_exams_command(text,jsonb) from public,anon;
grant execute on function public.evzon_exams_portal(uuid),public.evzon_exams_command(text,jsonb) to authenticated;
;
