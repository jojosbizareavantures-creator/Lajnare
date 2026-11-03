-- All fixtures are rolled back; no applicants, users or audits are left behind.
begin;
do $$
declare aid uuid:=gen_random_uuid();uid uuid:=gen_random_uuid();req uuid:=gen_random_uuid();rid uuid;refcode text;k text;p text;sig text;d jsonb;payload jsonb;result jsonb;bad boolean;updated timestamptz;i integer;
begin
 insert into evzon_private.admin_bootstrap(email) values('qa-app-admin-'||aid||'@example.invalid');
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values(aid,'qa-app-admin-'||aid||'@example.invalid',now(),'{"name":"Application test admin"}'),(uid,'qa-app-ref-'||uid||'@example.invalid',now(),'{"name":"Application test referrer"}');
 update public.evzon_profiles set status='Approved' where id=uid;
 select code into refcode from public.evzon_profiles where id=uid;
 select secret into k from evzon_private.application_ingest_config where id;
 d:=jsonb_build_object('first_name','Application','last_name','Test','country','North Macedonia','city','Skopje','date_of_birth','2000-01-15','phone','+38970123456','email','qa-app-'||req||'@example.invalid','gender','F','equipment','Laptop','message','Test message','experience','Beginner','availability','Evenings','language','en','adult',true,'consent',true,'code','');
 payload:=jsonb_build_object('data',d,'request_id',req,'sent_at',now(),'meta',jsonb_build_object('ip_address','192.0.2.123','user_agent','QA test','browser','Unknown','os','Unknown','device_type','Unknown','consent_version','2026-10-18'));
 p:=payload::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';
 bad:=false;begin perform public.evzon_submit_application(p,repeat('0',64));exception when others then bad:=sqlerrm like '%EVZON_FORBIDDEN%';end;if not bad then raise exception 'FAIL unsigned submission';end if;
 result:=public.evzon_submit_application(p,sig);if result<>'{"submitted":true}'::jsonb then raise exception 'FAIL direct application';end if;
 result:=public.evzon_submit_application(p,sig);
 bad:=false;begin perform public.evzon_apply(refcode,d);exception when insufficient_privilege then bad:=true;end;if not bad then raise exception 'FAIL legacy anonymous entry point';end if;
 bad:=false;begin perform count(*) from public.evzon_applications;exception when insufficient_privilege then bad:=true;end;if not bad then raise exception 'FAIL anonymous application visibility';end if;
 bad:=false;begin perform secret from evzon_private.application_ingest_config;exception when insufficient_privilege then bad:=true;end;if not bad then raise exception 'FAIL secret access';end if;
 execute 'reset role';
 if (select count(*) from public.evzon_applications where id=req)<>1 then raise exception 'FAIL retry idempotence';end if;
 if not exists(select 1 from public.evzon_applications where id=req and ip_address='192.0.2.123' and status='New' and referral_id is null) then raise exception 'FAIL trusted metadata or direct application';end if;
 -- Same-email retry cannot overwrite a submitted application.
 p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||'{"first_name":"Overwrite attempt"}'::jsonb))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';perform public.evzon_submit_application(p,sig);execute 'reset role';
 if (select first_name from public.evzon_applications where id=req)<>'Application' then raise exception 'FAIL duplicate overwrite';end if;
 -- Even a signed payload is revalidated in the database.
 for i in 1..3 loop
  p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('email','qa-invalid-'||i||req||'@example.invalid')||case i when 1 then jsonb_build_object('date_of_birth',(current_date-interval '17 years')::date) when 2 then '{"equipment":"Phone"}'::jsonb else '{"consent":false}'::jsonb end))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
  execute 'set local role anon';bad:=false;begin perform public.evzon_submit_application(p,sig);exception when others then bad:=true;end;execute 'reset role';if not bad then raise exception 'FAIL invalid signed payload %',i;end if;
 end loop;
 -- Optional code creates the existing referral and attributes it server-side.
 p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('email','qa-ref-app-'||req||'@example.invalid','code',refcode)))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';perform public.evzon_submit_application(p,sig);execute 'reset role';
 select referral_id into rid from public.evzon_applications where email='qa-ref-app-'||req||'@example.invalid';
 if rid is null or (select referrer_id from public.evzon_referrals where id=rid)<>uid then raise exception 'FAIL referral attribution';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);execute 'set local role authenticated';
 if exists(select 1 from public.evzon_applications) then raise exception 'FAIL referrer PII visibility';end if;
 bad:=false;begin perform public.evzon_review_application(req,'Accepted','Unauthorized',now());exception when others then bad:=sqlerrm like '%EVZON_FORBIDDEN%';end;if not bad then raise exception 'FAIL referrer review';end if;
 execute 'reset role';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',aid,'role','authenticated')::text,true);execute 'set local role authenticated';
 select updated_at into updated from public.evzon_applications where id=req;if updated is null then raise exception 'FAIL admin read';end if;
 result:=public.evzon_review_application(req,'Interview','Reviewed test',updated);if result->>'status'<>'Interview' then raise exception 'FAIL admin review';end if;
 bad:=false;begin perform public.evzon_review_application(req,'Accepted','Stale test',updated);exception when others then bad:=sqlerrm like '%EVZON_CONFLICT%';end;if not bad then raise exception 'FAIL review conflict';end if;
 bad:=false;begin update public.evzon_applications set email='tamper@example.invalid' where id=req;exception when insufficient_privilege then bad:=true;end;if not bad then raise exception 'FAIL contact rewrite';end if;
 execute 'reset role';
 if not exists(select 1 from evzon_private.audit where actor=aid and action='Application reviewed' and after_data->>'id'=req::text) then raise exception 'FAIL review audit';end if;
 update public.evzon_profiles set status='Suspended' where id=aid;execute 'set local role authenticated';
 if exists(select 1 from public.evzon_applications) then raise exception 'FAIL suspended admin read';end if;execute 'reset role';
 -- Five submissions from the same IP in an hour are allowed, the sixth is rejected.
 for i in 1..4 loop
  p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('email','qa-rate-'||i||req||'@example.invalid')))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
  execute 'set local role anon';bad:=false;begin perform public.evzon_submit_application(p,sig);exception when others then bad:=sqlerrm like '%Too many applications%';end;execute 'reset role';
  if (i=4)<>bad then raise exception 'FAIL rate limit %',i;end if;
 end loop;
 perform set_config('evzon.application_test','PASS: signed submissions, direct applications, retries, duplicates, required equipment, age, consent, referral attribution, anonymous denial, referrer isolation, admin review, audit, concurrency, suspension and rate limiting',true);
end $$;
select current_setting('evzon.application_test') as result;
rollback;
