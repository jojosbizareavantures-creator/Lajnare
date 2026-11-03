create or replace function evzon_private.portal() returns jsonb language plpgsql security definer set search_path='' as $$
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
create or replace function evzon_private.command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
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
;
