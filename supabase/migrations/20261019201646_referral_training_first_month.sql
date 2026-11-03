-- Two one-time referral milestones. Existing terms and earned rewards remain unchanged.
alter table public.evzon_referral_config
 add column program_version text not null default 'milestones_v2' check(program_version='milestones_v2'),
 add column training_bonus numeric not null default 20 check(training_bonus between 0 and 100000),
 add column training_days integer not null default 7 check(training_days between 1 and 365),
 add column first_month_bonus numeric not null default 30 check(first_month_bonus between 0 and 100000);
alter table public.evzon_referrals
 add column training_started_on date,
 add column training_days_completed integer not null default 0 check(training_days_completed between 0 and 365),
 add column training_completed_on date,
 add column first_month_completed_on date;
alter table public.evzon_referrals drop constraint evzon_referrals_stage_check;
alter table public.evzon_referrals add constraint evzon_referrals_stage_check check(stage in ('Submitted','Under Review','Interview','Training','Training Completed','Hired','Active','30-Day Milestone Completed','First Month Completed','Rejected','Withdrawn'));
alter table public.evzon_rewards alter column worker_id drop not null;
alter table public.evzon_rewards drop constraint evzon_rewards_kind_check;
alter table public.evzon_rewards add constraint evzon_rewards_kind_check check(kind in ('Hire','Retention','Commission','Training','First month'));
create unique index evzon_rewards_v2_referral_once on public.evzon_rewards(referral_id,kind) where kind in ('Training','First month');
create unique index evzon_rewards_v2_worker_once on public.evzon_rewards(worker_id,kind) where kind in ('Training','First month') and worker_id is not null;
-- Only these published offer fields are readable anonymously; no resources, account or financial data.
grant select(training_bonus,training_days,first_month_bonus) on public.evzon_referral_config to anon;
create policy offer_read on public.evzon_referral_config for select to anon using(true);

create or replace function evzon_private.terms() returns jsonb language sql stable set search_path='' as $$
select jsonb_build_object('program_version',program_version,'training_bonus',training_bonus,'training_days',training_days,'first_month_bonus',first_month_bonus,'hire_bonus',hire_bonus,'retention_bonus',retention_bonus,'retention_days',retention_days,'commission_rate',0,'commission_months',commission_months,'require_collected',require_collected)
from public.evzon_referral_config where id;
$$;

CREATE OR REPLACE FUNCTION evzon_private.refresh_legacy_rewards()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r public.evzon_referrals; s jsonb; w jsonb; days int; eligible boolean; p evzon_private.periods; amount numeric; exp text; added uuid;
begin
 select state into s from public.evzon_workspace where id;
 for r in select * from public.evzon_referrals where worker_id is not null and coalesce(terms->>'program_version','legacy')<>'milestones_v2' loop
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
end $function$
;
create or replace function evzon_private.refresh_rewards() returns void language plpgsql set search_path='' as $$
declare r public.evzon_referrals; s jsonb; w jsonb; v_kind text; v_amount numeric; eligible boolean; v_explanation text; added uuid;
begin
 perform evzon_private.refresh_legacy_rewards();
 select state into s from public.evzon_workspace where id;
 for r in select * from public.evzon_referrals where terms->>'program_version'='milestones_v2' loop
  w:=null;
  if r.worker_id is not null then
   select x into w from jsonb_array_elements(s->'workers') x where x->>'id'=r.worker_id;
   update public.evzon_referrals set worker_status=coalesce(w->>'status','Terminated') where id=r.id;
   -- Attaching a worker adds cost attribution, never changes a reward's beneficiary or amount.
   update public.evzon_rewards set worker_id=r.worker_id where referral_id=r.id and worker_id is null;
  end if;
  foreach v_kind in array array['Training','First month'] loop
   eligible:=r.training_complete and r.training_days_completed>=(r.terms->>'training_days')::integer
    and r.training_completed_on<=current_date and r.training_started_on is not null
    and r.training_completed_on-r.training_started_on+1>=r.training_days_completed
    and r.stage not in ('Rejected','Withdrawn');
   if v_kind='Training' then
    v_amount:=(r.terms->>'training_bonus')::numeric;
    v_explanation:='Completed '||(r.terms->>'training_days')||' training days, verified by an administrator.';
   else
    eligible:=eligible and w->>'status'='Active' and r.hired_on is not null
     and r.first_month_completed_on>=(r.hired_on+interval '1 month')::date and r.first_month_completed_on<=current_date;
    v_amount:=(r.terms->>'first_month_bonus')::numeric;
    v_explanation:='First working month completed and verified by an administrator.';
   end if;
   insert into public.evzon_rewards(referral_id,referrer_id,worker_id,kind,period,explanation,terms)
    values(r.id,r.referrer_id,r.worker_id,v_kind,date_trunc('month',current_date)::date,
     case when v_kind='Training' then 'Awaiting verified training completion.' else 'Awaiting verified first working month.' end,r.terms) on conflict do nothing;
   if coalesce(eligible,false) then
    update public.evzon_rewards q set status='Pending review',amount=case when v_kind='Training' then (q.terms->>'training_bonus')::numeric else (q.terms->>'first_month_bonus')::numeric end,
     earned_at=now(),period=date_trunc('month',current_date)::date,explanation=v_explanation
     where q.referral_id=r.id and q.kind=v_kind and status='Not yet eligible' returning id into added;
    if added is not null then
     insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,v_kind||' reward earned for '||r.candidate_name||'; awaiting review.');
    end if;
   end if;
  end loop;
 end loop;
 update public.evzon_rewards q set status='Payable' where q.status='Approved'
  and q.kind in ('Training','First month') and exists(select 1 from public.evzon_profiles p where p.id=q.referrer_id and p.status='Approved' and p.role='REFERRER');
end $$;
revoke all on function evzon_private.refresh_legacy_rewards() from public,anon,authenticated;

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
  if p_data->>'status' in ('Approved','Payable','Paid') and not exists(select 1 from public.evzon_profiles p where p.id=q.referrer_id and p.status='Approved' and p.role='REFERRER') then raise exception 'EVZON_INVALID: Approve the partner account before approving or paying rewards'; end if;
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
CREATE OR REPLACE FUNCTION evzon_private.apply(p_code text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.evzon_profiles; rid uuid;
begin
 select * into p from public.evzon_profiles where code=upper(trim(p_code)) and status in ('Pending','Approved') and role='REFERRER' and exists(select 1 from auth.users u where u.id=public.evzon_profiles.id and u.email_confirmed_at is not null);
 if p.id is null then raise exception 'EVZON_INVALID: Referral link is unavailable'; end if;
 if coalesce(p_data->>'website','')<>'' then return '{"submitted":true}'::jsonb; end if;
 if length(trim(coalesce(p_data->>'name',''))) not between 1 and 120 or coalesce(p_data->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_data->>'email')>254 or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'notes',''))>2000 or not coalesce((p_data->>'consent')::boolean,false) or not coalesce((p_data->>'adult')::boolean,false) then raise exception 'EVZON_INVALID: Complete the required fields and confirmations'; end if;
 if lower(trim(p_data->>'email'))=lower(p.email) then raise exception 'EVZON_INVALID: You cannot refer yourself'; end if;
 perform pg_advisory_xact_lock(hashtext('application-email:'||lower(trim(p_data->>'email'))));
 perform pg_advisory_xact_lock(hashtext(p.id::text));
 if (select count(*) from public.evzon_referrals where referrer_id=p.id and created_at>now()-interval '1 day')>=30 then raise exception 'EVZON_INVALID: Submission limit reached; please try tomorrow'; end if;
 if exists(select 1 from evzon_private.contacts where email=lower(trim(p_data->>'email'))) then return '{"submitted":true}'::jsonb; end if;
 insert into public.evzon_referrals(referrer_id,candidate_name,source,terms) values(p.id,trim(p_data->>'name'),'Referral link',evzon_private.terms()) returning id into rid;
 insert into evzon_private.contacts(referral_id,email,phone,notes) values(rid,lower(trim(p_data->>'email')),coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''));
 insert into public.evzon_events(referrer_id,referral_id,message) values(p.id,rid,'New application received: '||trim(p_data->>'name'));
 return '{"submitted":true}'::jsonb;
exception when unique_violation then return '{"submitted":true}'::jsonb;
end $function$
;
CREATE OR REPLACE FUNCTION evzon_private.submit_application(p_payload text, p_signature text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;d jsonb;m jsonb;k text;req uuid;ip inet;birth date;years integer;rid uuid;pid uuid;mail text;refcode text;
begin
 if p_payload is null or octet_length(p_payload)>32000 or p_signature is null or p_signature !~ '^[0-9a-f]{64}$' then raise exception 'EVZON_FORBIDDEN';end if;
 select secret into k from evzon_private.application_ingest_config where id;
 if k is null or encode(extensions.hmac(p_payload,k,'sha256'),'hex')<>p_signature then raise exception 'EVZON_FORBIDDEN';end if;
 v:=p_payload::jsonb;d:=v->'data';m:=v->'meta';req:=(v->>'request_id')::uuid;
 if v->>'sent_at' is null or abs(extract(epoch from (now()-(v->>'sent_at')::timestamptz)))>300 then raise exception 'EVZON_FORBIDDEN';end if;
 if req is null or d is null or m is null then raise exception 'EVZON_INVALID: Check your application details.';end if;
 if exists(select 1 from public.evzon_applications where id=req) then return '{"submitted":true}'::jsonb;end if;
 if not coalesce((d->>'adult')::boolean,false) or not coalesce((d->>'consent')::boolean,false) then raise exception 'EVZON_INVALID: Confirm the age requirement and application privacy notice.';end if;
 birth:=(d->>'date_of_birth')::date;
 years:=extract(year from age((now() at time zone 'Europe/Skopje')::date,birth));
 if birth is null or birth<date '1900-01-01' or years<18 then raise exception 'EVZON_INVALID: You must be at least 18 to apply.';end if;
 if d->>'phone' !~ '^\+?[0-9 ().-]+$' or length(regexp_replace(d->>'phone','[^0-9]','','g')) not between 7 and 15 then raise exception 'EVZON_INVALID: Enter a valid phone number, including your country code.';end if;
 mail:=lower(trim(d->>'email'));refcode:=upper(trim(coalesce(d->>'code','')));ip:=nullif(m->>'ip_address','')::inet;
 -- Locks make email deduplication and IP limits safe under concurrent submissions.
 if ip is not null then
  perform pg_advisory_xact_lock(hashtext('application-ip:'||ip::text));
  if (select count(*) from public.evzon_applications where ip_address=ip and created_at>now()-interval '1 hour')>=5
   or (select count(*) from public.evzon_applications where ip_address=ip and created_at>now()-interval '1 day')>=20 then raise exception 'EVZON_INVALID: Too many applications. Please try again later.';end if;
 end if;
 perform pg_advisory_xact_lock(hashtext('application-email:'||mail));
 if exists(select 1 from public.evzon_applications where email=mail and created_at>now()-interval '1 day') then return '{"submitted":true}'::jsonb;end if;
 if refcode<>'' then
  select id into pid from public.evzon_profiles where public.evzon_profiles.code=refcode and status in ('Pending','Approved') and role='REFERRER' and exists(select 1 from auth.users u where u.id=public.evzon_profiles.id and u.email_confirmed_at is not null);
  if pid is null then raise exception 'EVZON_INVALID: Check the referral code, or leave it empty to apply directly.';end if;
  perform evzon_private.apply(refcode,jsonb_build_object('name',left(trim(d->>'first_name')||' '||trim(d->>'last_name'),120),'email',mail,'phone',d->>'phone','notes',d->>'message','adult',true,'consent',true));
  -- Preserve the original attribution if this email was already referred. Never transfer a candidate on retry.
  select r.id,p.code into rid,refcode from public.evzon_referrals r join evzon_private.contacts c on c.referral_id=r.id join public.evzon_profiles p on p.id=r.referrer_id where c.email=mail;
 end if;
 insert into public.evzon_applications(id,first_name,last_name,country,city,date_of_birth,age_at_submission,phone,email,gender,equipment,message,experience,availability,language,referral_id,referral_code,consent_version,ip_address,user_agent,browser,os,device_type)
 values(req,trim(d->>'first_name'),trim(d->>'last_name'),trim(d->>'country'),trim(d->>'city'),birth,years,trim(d->>'phone'),mail,d->>'gender',d->>'equipment',coalesce(d->>'message',''),coalesce(d->>'experience',''),coalesce(d->>'availability',''),d->>'language',rid,case when rid is null then '' else refcode end,m->>'consent_version',ip,m->>'user_agent',m->>'browser',m->>'os',m->>'device_type');
 return '{"submitted":true}'::jsonb;
end $function$
;
CREATE OR REPLACE FUNCTION evzon_private.sync_workers(s jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    update public.evzon_rewards set worker_id=r.worker_id where referral_id=r.id and worker_id is null;
    perform evzon_private.audit('Worker referral attribution corrected',before_r,to_jsonb(r));
    insert into public.evzon_events(referrer_id,referral_id,message) values(r.referrer_id,r.id,'Administrator updated worker attribution. Earned rewards keep their original beneficiary and terms.');
   end if;
  end if;
 end loop;
end $function$
;
notify pgrst,'reload schema';
;
