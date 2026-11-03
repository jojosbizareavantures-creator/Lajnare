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
  if not exists(select 1 from public.evzon_profiles where id=(w->>'referrerId')::uuid and role='REFERRER' and status='Approved') then raise exception 'EVZON_INVALID: Select an approved referrer'; end if;
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
 'audit',case when admin then (select coalesce(jsonb_agg(to_jsonb(a) order by created_at desc),'[]') from (select * from evzon_private.audit order by created_at desc limit 200) a) else '[]'::jsonb end) into result;
 return result;
end $$;

revoke execute on function evzon_private.validate_workspace(jsonb),evzon_private.sync_workers(jsonb),evzon_private.portal() from public,anon,authenticated;
;
