create or replace function evzon_private.sync_workers(s jsonb) returns void language plpgsql set search_path='' as $$
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
