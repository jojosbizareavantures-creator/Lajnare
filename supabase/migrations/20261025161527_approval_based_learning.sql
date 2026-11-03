CREATE OR REPLACE FUNCTION evzon_private.training_day_access(p_day integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and (
 evzon_private.is_admin() or (
 evzon_private.is_chatter() and exists(
 select 1 from public.evzon_chatter_accounts a join public.evzon_chatter_lessons l on l.day=p_day
 where a.id=auth.uid() and a.completed_at is null and not a.must_change_password and l.published
 and (now() at time zone 'Europe/Skopje')::date>=a.training_start+(case when p_day<=5 then 0 else p_day-1 end)
 and (select count(*) from public.evzon_chatter_progress p where p.chatter_id=a.id and p.day<p_day and p.status='Approved')=p_day-1
 )))
$function$
;
CREATE OR REPLACE FUNCTION evzon_private.chatter_command(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me public.evzon_profiles; admin boolean; a public.evzon_chatter_accounts; d int; localday date:=(now() at time zone 'Europe/Skopje')::date; cfg evzon_private.chatter_config; q jsonb; score numeric; correct_count int:=0; attempt_id uuid; v_id uuid; s jsonb; w jsonb; sh jsonb; entry public.evzon_chatter_time; pay public.evzon_chatter_payouts; changed boolean:=false; hours numeric; regular numeric; overtime numeric; v_feedback text;begin
 select * into me from public.evzon_profiles where id=auth.uid();admin:=evzon_private.is_admin();
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>150000 then raise exception 'EVZON_INVALID: Invalid request';end if;
 perform pg_advisory_xact_lock(782541);
 select state into s from public.evzon_workspace where id for update;
 select * into cfg from evzon_private.chatter_config where id;
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
  if d is null or d not between 1 and 7 or a.completed_at is not null or localday<a.training_start+(case when d<=5 then 0 else d-1 end) then raise exception 'EVZON_INVALID: This training stage is not available yet';end if;
  if (select count(*) from public.evzon_chatter_progress where chatter_id=a.id and day<d and status='Approved')<>d-1 then raise exception 'EVZON_INVALID: Complete previous stages and receive trainer approval first';end if;
  if not exists(select 1 from public.evzon_chatter_lessons where day=d and published and length(trim(content))>0) then raise exception 'EVZON_INVALID: Your trainer has not published this lesson yet';end if;
  if d>=5 and cfg.exam_enabled and a.hired_at is null then raise exception 'EVZON_INVALID: Pass the knowledge exam first';end if;
  if exists(select 1 from public.evzon_chatter_progress where chatter_id=a.id and day=d and status='Approved') then raise exception 'EVZON_INVALID: This stage is already approved';end if;
  insert into public.evzon_chatter_progress(chatter_id,day,status,submitted_at) values(a.id,d,'Submitted',now()) on conflict(chatter_id,day) do update set status='Submitted',submitted_at=now();
 elsif p_action='exam' then
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
   d:=(p_data->>'day')::int;v_feedback:=trim(coalesce(p_data->>'feedback',''));
   if a.id is null or a.completed_at is not null or d is null or d not between 1 and 7 or p_data->>'status' not in ('Approved','Changes needed') then raise exception 'EVZON_INVALID: Select an unfinished training stage';end if;
   if length(v_feedback)<3 then raise exception 'EVZON_INVALID: Add trainer feedback';end if;
   if not exists(select 1 from public.evzon_chatter_progress where chatter_id=a.id and day=d and status in ('Submitted','Changes needed')) then raise exception 'EVZON_INVALID: The chatter must submit this stage first';end if;
   if p_data->>'status'='Approved' then
    if not exists(select 1 from public.evzon_chatter_lessons where day=d and published and length(trim(content))>0) then raise exception 'EVZON_INVALID: Your trainer has not published this lesson yet';end if;
    if localday<a.training_start+(case when d<=5 then 0 else d-1 end) or (select count(*) from public.evzon_chatter_progress where chatter_id=a.id and day<d and status='Approved')<>d-1 or (d>=5 and cfg.exam_enabled and a.hired_at is null) then raise exception 'EVZON_INVALID: Previous stages and any required exam must be completed in order';end if;
    if d=7 and not coalesce((p_data->>'ceo_review')::boolean,false) then raise exception 'EVZON_INVALID: Confirm the Discord screen-share trial and CEO feedback';end if;
   end if;
   update public.evzon_chatter_progress set status=p_data->>'status',feedback=v_feedback,approved_at=case when p_data->>'status'='Approved' then now() else null end,approved_by=me.id where chatter_id=a.id and day=d;
   if d=7 and p_data->>'status'='Approved' then
    if not exists(select 1 from jsonb_array_elements(s->'workers') x where x->>'id'=a.worker_id and x->>'status'='Training') then raise exception 'EVZON_INVALID: The linked worker must have Training status';end if;
    update public.evzon_chatter_accounts set completed_at=now(),hired_at=coalesce(hired_at,now()) where id=a.id;
    s:=jsonb_set(s,'{workers}',(select jsonb_agg(case when x->>'id'=a.worker_id then x||jsonb_build_object('status','Active','trainingComplete',true,'assessmentPassed',true,'start',localday) else x end) from jsonb_array_elements(s->'workers') x));changed:=true;
    update public.evzon_referrals set training_complete=true,assessment_passed=true,training_started_on=a.training_start,training_completed_on=localday,training_days_completed=7,hired_on=coalesce(hired_on,localday),worker_status='Active',stage='Active',updated_at=now() where worker_id=a.worker_id and stage not in ('Rejected','Withdrawn');
   end if;
  elsif p_action='close-clock' then
   if length(trim(coalesce(p_data->>'notes','')))<3 then raise exception 'EVZON_INVALID: Add a reason for closing this clock';end if;
   update public.evzon_chatter_time set clock_out=now(),notes=trim(p_data->>'notes') where id=(p_data->>'id')::uuid and clock_out is null and status='Pending';
   if not found then raise exception 'EVZON_INVALID: This clock is already closed or missing';end if;
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
end $function$
;
CREATE OR REPLACE FUNCTION evzon_private.chatter_portal()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me public.evzon_profiles; admin boolean; a public.evzon_chatter_accounts; s jsonb; w jsonb; cfg jsonb;begin
 select * into me from public.evzon_profiles where id=auth.uid();
 admin:=evzon_private.is_admin();
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 select * into a from public.evzon_chatter_accounts where id=me.id;
 select state into s from public.evzon_workspace where id;
 select x into w from jsonb_array_elements(s->'workers') x where x->>'id'=a.worker_id;
 select to_jsonb(c)-'id' into cfg from evzon_private.chatter_config c where id;
 if not admin then
  cfg:=jsonb_set(cfg,'{questions}',case when a.completed_at is null and (now() at time zone 'Europe/Skopje')::date>=a.training_start and exists(select 1 from public.evzon_chatter_lessons where day=5 and published and length(trim(content))>0) and (select count(*) from public.evzon_chatter_progress where chatter_id=me.id and day<5 and status='Approved')=4 and (cfg->>'exam_enabled')::boolean then (select coalesce(jsonb_agg(q-'correct'),'[]') from jsonb_array_elements(cfg->'questions') q) else '[]'::jsonb end);
 end if;
 return jsonb_build_object('profile',to_jsonb(me),'server_time',now(),'today',(now() at time zone 'Europe/Skopje')::date,
 'accounts',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('name',p.name,'email',p.email,'status',p.status) order by c.created_at desc),'[]') from public.evzon_chatter_accounts c join public.evzon_profiles p on p.id=c.id where admin or c.id=me.id),
 'lessons',(select coalesce(jsonb_agg(case when admin or published then to_jsonb(l) else to_jsonb(l)||jsonb_build_object('content','','content_mk','') end order by day),'[]') from public.evzon_chatter_lessons l where admin or a.completed_at is null),
 'progress',(select coalesce(jsonb_agg(to_jsonb(p) order by p.day),'[]') from public.evzon_chatter_progress p where admin or p.chatter_id=me.id),
 'totals',jsonb_build_object('approved_due',(select coalesce(sum(amount),0) from public.evzon_chatter_payouts where status='Approved' and (admin or chatter_id=me.id)),'paid',(select coalesce(sum(amount),0) from public.evzon_chatter_payouts where status='Paid' and (admin or chatter_id=me.id)),'approved_month_hours',(select coalesce(sum(regular_hours+overtime_hours),0) from public.evzon_chatter_time where status='Approved' and (admin or chatter_id=me.id) and date_trunc('month',clock_in at time zone 'Europe/Skopje')=date_trunc('month',now() at time zone 'Europe/Skopje'))),
 'config',cfg,'attempts',(select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]') from (select * from public.evzon_chatter_attempts where admin or chatter_id=me.id order by created_at desc limit 1000) p),
 'entries',(select coalesce(jsonb_agg(to_jsonb(p) order by p.clock_in desc),'[]') from (select * from public.evzon_chatter_time where admin or chatter_id=me.id order by clock_in desc limit 2000) p),
 'payouts',(select coalesce(jsonb_agg(to_jsonb(p) order by p.period desc,p.created_at desc),'[]') from (select * from public.evzon_chatter_payouts where admin or chatter_id=me.id order by period desc,created_at desc limit 2000) p),
 'announcements',(select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]') from (select * from public.evzon_chatter_announcements where admin or published order by created_at desc limit 100) p),
 'worker',case when w is null then null else jsonb_build_object('id',w->'id','name',w->'name','status',w->'status','salary',w->'salary','bonus',w->'bonus','payroll',w->'payroll','wageRate',w->'wageRate','overtimeRate',w->'overtimeRate','availability',w->'availability','shift',w->'shift') end,
 'shifts',(select coalesce(jsonb_agg(jsonb_build_object('id',x->'id','date',x->'date','start',x->'start','scheduled',x->'scheduled','actual',x->'actual','overtime',x->'overtime','approved',x->'approved','absence',x->'absence') order by x->>'date',x->>'start'),'[]') from jsonb_array_elements(s->'shifts') x where coalesce(nullif(x->>'replacement',''),x->>'worker')=a.worker_id and (x->>'date')::date between (now() at time zone 'Europe/Skopje')::date-31 and (now() at time zone 'Europe/Skopje')::date+90));
end $function$
;
update public.evzon_chatter_lessons set title='Learning material '||day,title_mk='Материјал за учење '||day,content=replace(content,'submit the day for trainer review','submit the material for trainer review'),content_mk=replace(content_mk,'испратете го денот на проверка','испратете го материјалот на проверка') where day between 1 and 4;;
update public.evzon_chatter_lessons set title='Practicing for exams',title_mk='Подготовка за испити',content='',content_mk='',published=false where day=5;
;
