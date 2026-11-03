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

revoke execute on function evzon_private.refresh_rewards() from public,anon,authenticated;
;
