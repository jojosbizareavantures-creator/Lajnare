-- Do not overwrite a concurrently changed training function.
do $$ begin
 if md5(pg_get_functiondef('evzon_private.chatter_command(text,jsonb)'::regprocedure))<>'61880b702d845e511c2249fc00acb422' or md5(pg_get_functiondef('evzon_private.chatter_portal()'::regprocedure))<>'1feb2f94a56be7a9af55f90af052f35e' then
  raise exception 'Training functions changed; review the current definitions before activation';
 end if;
end $$;
-- Disambiguate the question snapshot variable during server-side scoring.
create or replace function evzon_private.exams_command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin(); who uuid; a public.evzon_chatter_accounts; g evzon_private.exam_permissions; attempt evzon_private.exam_attempts; question_value jsonb; opt jsonb; k text; val jsonb; bank jsonb; sequence text; tries integer:=0; total_count integer; right_count integer:=0; threshold integer; key text; permission uuid; note text;begin
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
   select v into question_value from jsonb_array_elements(attempt.questions) v where v->>'id'=k;
   if question_value is null or jsonb_typeof(val)<>'string' or not exists(select 1 from jsonb_array_elements(question_value->'options') o where o->>'id'=val#>>'{}') then raise exception 'EVZON_INVALID: Invalid question or answer';end if;
  end loop;
  if p_action='submit' then
   if (select count(*) from jsonb_object_keys(p_data->'answers'))<>attempt.total then raise exception 'EVZON_INVALID: Answer every question before submitting';end if;
   for question_value in select * from jsonb_array_elements(attempt.questions) loop
    if p_data->'answers'->>(question_value->>'id')=question_value->>'correct' then right_count:=right_count+1;end if;
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

-- Replace only the retired exam branches, retaining all other training logic.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('evzon_private.chatter_command(text,jsonb)'::regprocedure);
 definition:=replace(definition,$old$ elsif p_action='exam' then
  if admin then raise exception 'EVZON_FORBIDDEN';end if;
  select * into cfg from evzon_private.chatter_config where id;
  if not cfg.exam_enabled or jsonb_array_length(cfg.questions)=0 or not exists(select 1 from public.evzon_chatter_lessons where day=5 and published and length(trim(content))>0) then raise exception 'EVZON_INVALID: Your trainer has not published the exam yet';end if;
  if a.hired_at is not null or a.completed_at is not null then raise exception 'EVZON_INVALID: Your exam is already passed';end if;
  if localday<a.training_start or (select count(*) from public.evzon_chatter_progress where chatter_id=a.id and day<5 and status='Approved')<>4 then raise exception 'EVZON_INVALID: Complete learning materials 1–4 before the exam';end if;
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
$old$,$new$ elsif p_action='exam' then
  raise exception 'EVZON_INVALID: Use the authorized final exam in Practicing for exams';
$new$);
 definition:=replace(definition,$old$  elsif p_action='exam-config' then
   if jsonb_typeof(p_data->'questions') is distinct from 'array' or jsonb_array_length(p_data->'questions')>60 then raise exception 'EVZON_INVALID: Add up to 60 questions';end if;
   if (p_data->>'exam_enabled')::boolean and jsonb_array_length(p_data->'questions')=0 then raise exception 'EVZON_INVALID: Add questions before publishing';end if;
   for q in select * from jsonb_array_elements(p_data->'questions') loop
    if coalesce(q->>'id','')='' or length(trim(coalesce(q->>'question',''))) not between 1 and 2000 or jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options')<>4 or coalesce(q->>'correct','')!~'^[0-3]$' then raise exception 'EVZON_INVALID: Each question needs four answers and one correct choice';end if;
    if exists(select 1 from jsonb_array_elements_text(q->'options') x where length(trim(x)) not between 1 and 1000) then raise exception 'EVZON_INVALID: Fill in every answer option';end if;
   end loop;
   if (select count(*)<>count(distinct x->>'id') from jsonb_array_elements(p_data->'questions') x) then raise exception 'EVZON_INVALID: Duplicate question IDs';end if;
   if coalesce(p_data->>'discord_url','')<>'' and p_data->>'discord_url'!~'^https://(discord\.gg/|discord\.com/)' then raise exception 'EVZON_INVALID: Use a Discord invite or channel URL';end if;
   update evzon_private.chatter_config set pass_score=(p_data->>'pass_score')::int,max_attempts=(p_data->>'max_attempts')::int,exam_enabled=(p_data->>'exam_enabled')::boolean,questions=p_data->'questions',discord_url=coalesce(p_data->>'discord_url','') where id;
$old$,$new$  elsif p_action='exam-config' then
   raise exception 'EVZON_INVALID: Manage practice and final exams in the Exams tab';
$new$);
 execute definition;
 definition:=pg_get_functiondef('evzon_private.chatter_portal()'::regprocedure);
 definition:=replace(definition,$old$ if not admin then
  cfg:=jsonb_set(cfg,'{questions}',case when a.completed_at is null and (now() at time zone 'Europe/Skopje')::date>=a.training_start and exists(select 1 from public.evzon_chatter_lessons where day=5 and published and length(trim(content))>0) and (select count(*) from public.evzon_chatter_progress where chatter_id=me.id and day<5 and status='Approved')=4 and (cfg->>'exam_enabled')::boolean then (select coalesce(jsonb_agg(q-'correct'),'[]') from jsonb_array_elements(cfg->'questions') q) else '[]'::jsonb end);
 end if;
$old$,$new$ cfg:=jsonb_set(cfg,'{questions}','[]'::jsonb);
$new$);
 execute definition;
end $patch$;
update evzon_private.chatter_config set exam_enabled=true where id;
update public.evzon_chatter_lessons set published=true,content=title,content_mk=title_mk where day=5;
;
