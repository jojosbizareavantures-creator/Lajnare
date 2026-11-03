CREATE OR REPLACE FUNCTION evzon_private.command(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not coalesce((p_data->>'adult')::boolean,false) or lower(trim(p_data->>'email'))=lower(me.email) or length(trim(coalesce(p_data->>'name',''))) not between 1 and 120 or coalesce(p_data->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_data->>'email')>254 or length(coalesce(p_data->>'notes',''))>2000 or length(coalesce(p_data->>'phone',''))>60 or not coalesce((p_data->>'consent')::boolean,false) then raise exception 'EVZON_INVALID: Name, email and candidate consent are required'; end if;
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
  if exists(select 1 from public.evzon_rewards where referral_id=r.id and earned_at is not null and kind<>'Training') and r.hired_on is distinct from nullif(p_data->>'hired_on','')::date then raise exception 'EVZON_INVALID: Hiring date is locked after a reward is earned'; end if;
  if r.terms->>'program_version'='milestones_v2' then
   if coalesce((p_data->>'training_days_completed')::integer,0)<0 or coalesce((p_data->>'training_days_completed')::integer,0)>365 then raise exception 'EVZON_INVALID: Enter completed training days between 0 and 365'; end if;
   if nullif(p_data->>'training_started_on','')::date>current_date or nullif(p_data->>'training_completed_on','')::date>current_date or nullif(p_data->>'first_month_completed_on','')::date>current_date then raise exception 'EVZON_INVALID: Completion dates cannot be in the future'; end if;
   if coalesce((p_data->>'training_days_completed')::integer,0)>0 and (nullif(p_data->>'training_started_on','') is null or (p_data->>'training_days_completed')::integer>current_date-(p_data->>'training_started_on')::date+1) then raise exception 'EVZON_INVALID: Completed training days must fit the training dates'; end if;
   if coalesce((p_data->>'training_complete')::boolean,false) and
    (nullif(p_data->>'training_completed_on','') is null or nullif(p_data->>'training_started_on','') is null
     or coalesce((p_data->>'training_days_completed')::integer,0)<(r.terms->>'training_days')::integer
     or (p_data->>'training_completed_on')::date-(p_data->>'training_started_on')::date+1<(p_data->>'training_days_completed')::integer)
    then raise exception 'EVZON_INVALID: Verify all required training days and completion dates'; end if;
   if nullif(p_data->>'training_completed_on','') is not null and not coalesce((p_data->>'training_complete')::boolean,false) then raise exception 'EVZON_INVALID: Confirm training completion or clear its completion date'; end if;
   if nullif(p_data->>'hired_on','') is not null and nullif(p_data->>'training_completed_on','') is not null and (p_data->>'hired_on')::date<(p_data->>'training_completed_on')::date then raise exception 'EVZON_INVALID: Hiring cannot precede completed training'; end if;
   if nullif(p_data->>'first_month_completed_on','') is not null and
    (not coalesce((p_data->>'training_complete')::boolean,false) or nullif(p_data->>'hired_on','') is null
     or (p_data->>'first_month_completed_on')::date<((p_data->>'hired_on')::date+interval '1 month')::date
     or not exists(select 1 from jsonb_array_elements(s->'workers') w where w->>'id'=r.worker_id and w->>'status'='Active'))
    then raise exception 'EVZON_INVALID: Verify the first full working month after hiring and link an active worker'; end if;
   if exists(select 1 from public.evzon_rewards where referral_id=r.id and kind='Training' and earned_at is not null)
    and (r.training_started_on is distinct from nullif(p_data->>'training_started_on','')::date or r.training_completed_on is distinct from nullif(p_data->>'training_completed_on','')::date
     or r.training_days_completed is distinct from coalesce((p_data->>'training_days_completed')::integer,0) or r.training_complete is distinct from coalesce((p_data->>'training_complete')::boolean,false))
    then raise exception 'EVZON_INVALID: Earned training milestone is locked; use reward review for corrections'; end if;
   if exists(select 1 from public.evzon_rewards where referral_id=r.id and kind='First month' and earned_at is not null)
    and r.first_month_completed_on is distinct from nullif(p_data->>'first_month_completed_on','')::date then raise exception 'EVZON_INVALID: Earned first-month milestone is locked'; end if;
   update public.evzon_referrals set training_started_on=nullif(p_data->>'training_started_on','')::date,
    training_days_completed=coalesce((p_data->>'training_days_completed')::integer,0),
    training_completed_on=nullif(p_data->>'training_completed_on','')::date,
    first_month_completed_on=nullif(p_data->>'first_month_completed_on','')::date where id=r.id;
  end if;
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
  if p_data->>'status' in ('Approved','Payable','Paid') and not exists(select 1 from public.evzon_profiles beneficiary where beneficiary.id=q.referrer_id and beneficiary.status='Approved' and beneficiary.role='REFERRER') then raise exception 'EVZON_INVALID: Approve the partner account before approving or paying rewards'; end if;
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
  if p_data->>'training_bonus' is null or p_data->>'training_days' is null or p_data->>'first_month_bonus' is null then raise exception 'EVZON_INVALID: Enter both rewards and required training days'; end if;
  update public.evzon_referral_config set training_bonus=round((p_data->>'training_bonus')::numeric,2),training_days=(p_data->>'training_days')::integer,first_month_bonus=round((p_data->>'first_month_bonus')::numeric,2),resources=left(coalesce(p_data->>'resources',''),20000),updated_at=now() where id;
  perform evzon_private.audit('Referral defaults changed prospectively',old,p_data);
 elsif p_action<>'refresh' then raise exception 'EVZON_INVALID: Unknown action';
 end if;
 perform evzon_private.refresh_rewards();
 return evzon_private.portal() || jsonb_build_object('workspace',(select to_jsonb(ws) from public.evzon_workspace ws where id));
exception when unique_violation then raise exception 'EVZON_INVALID: This candidate, workday or reward is already recorded';
end $function$
;

update public.evzon_referral_config set resources=replace(resources,
'A hire bonus requires completed training, a passed assessment and an active hire. Retention counts approved days actually worked, not calendar days. Ongoing rewards follow the recorded program terms and are reviewed for each eligible period.',
'Two one-time rewards apply: the training reward after the required number of completed training days, and the first-month reward after the first full working month from the hiring date. Evzon verifies completed milestones. See your recorded terms for the amounts. Applications alone do not earn rewards. Partner approval is required before rewards can be approved and paid.')
where id;
notify pgrst,'reload schema';
;
