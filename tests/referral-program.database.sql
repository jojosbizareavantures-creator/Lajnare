-- Integration tests use disposable fixtures and roll back every change.
begin;
do $test$
declare aid uuid:=gen_random_uuid();partner uuid:=gen_random_uuid();other uuid:=gen_random_uuid();unverified uuid:=gen_random_uuid();req uuid:=gen_random_uuid();rid uuid;training_reward uuid;month_reward uuid;code text;other_code text;bad_code text;k text;payload jsonb;d jsonb;p text;sig text;result jsonb;bad boolean;s jsonb;milestones jsonb;hire date:=(current_date-interval '2 months')::date;cfg jsonb;
begin
 insert into evzon_private.admin_bootstrap(email) values('qa-program-admin-'||aid||'@example.invalid');
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (aid,'qa-program-admin-'||aid||'@example.invalid',now(),'{"name":"Program test admin"}'),
 (partner,'qa-partner-'||partner||'@example.invalid',now(),'{"name":"Program partner","role":"ADMIN"}'),
 (other,'qa-other-'||other||'@example.invalid',now(),'{"name":"Other partner"}'),
 (unverified,'qa-unverified-'||unverified||'@example.invalid',null,'{"name":"Unverified partner"}');
 if not exists(select 1 from public.evzon_profiles where id=partner and status='Pending' and role='REFERRER') then raise exception 'FAIL signup permissions'; end if;
 select p.code into code from public.evzon_profiles p where id=partner;
 select p.code into other_code from public.evzon_profiles p where id=other;
 select p.code into bad_code from public.evzon_profiles p where id=unverified;
 if code is null or code=other_code then raise exception 'FAIL unique registration codes'; end if;
 select secret into k from evzon_private.application_ingest_config where id;
 d:=jsonb_build_object('first_name','Referral','last_name','Candidate','country','North Macedonia','city','Skopje','date_of_birth','2000-01-15','phone','+38970123456','email','qa-program-'||req||'@example.invalid','gender','F','equipment','Laptop','message','QA referral','experience','Beginner','availability','Evenings','language','en','adult',true,'consent',true,'code',lower(code),'referrer_id',other);
 payload:=jsonb_build_object('data',d,'request_id',req,'sent_at',now(),'meta',jsonb_build_object('ip_address','192.0.2.222','user_agent','QA','browser','Unknown','os','Unknown','device_type','Unknown','consent_version','2026-10-18'));
 p:=payload::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';
 perform training_bonus,training_days,first_month_bonus from public.evzon_referral_config;
 bad:=false;begin perform resources from public.evzon_referral_config;exception when insufficient_privilege then bad:=true;end;if not bad then raise exception 'FAIL public offer leaks private resources';end if;
 perform public.evzon_submit_application(p,sig);
 perform public.evzon_submit_application(p,sig);
 execute 'reset role';
 select referral_id into rid from public.evzon_applications where id=req;
 if rid is null or (select referrer_id from public.evzon_referrals where id=rid)<>partner then raise exception 'FAIL pending verified code attribution';end if;
 if (select count(*) from public.evzon_applications where id=req)<>1 then raise exception 'FAIL idempotent application';end if;
 if not exists(select 1 from public.evzon_referrals where id=rid and terms->>'program_version'='milestones_v2') then raise exception 'FAIL terms snapshot';end if;
 -- A second referrer's link must never steal the existing candidate, even on a later application.
 update public.evzon_applications set created_at=now()-interval '2 days' where id=req;
 p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('code',other_code)))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';perform public.evzon_submit_application(p,sig);execute 'reset role';
 if exists(select 1 from public.evzon_applications where email=d->>'email' and (referral_id<>rid or referral_code<>code)) then raise exception 'FAIL original attribution preserved';end if;
 -- Unverified and suspended partners cannot create new referred applications.
 p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('email','qa-unverified-candidate-'||req||'@example.invalid','code',bad_code)))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';bad:=false;begin perform public.evzon_submit_application(p,sig);exception when others then bad:=sqlerrm like '%referral code%';end;execute 'reset role';if not bad then raise exception 'FAIL unverified code';end if;
 update public.evzon_profiles set status='Suspended' where id=other;
 p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('email','qa-suspended-candidate-'||req||'@example.invalid','code',other_code)))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';bad:=false;begin perform public.evzon_submit_application(p,sig);exception when others then bad:=sqlerrm like '%referral code%';end;execute 'reset role';if not bad then raise exception 'FAIL suspended code';end if;
 p:=(payload||jsonb_build_object('request_id',gen_random_uuid(),'data',d||jsonb_build_object('email','qa-partner-'||partner||'@example.invalid','code',code)))::text;sig:=encode(extensions.hmac(p,k,'sha256'),'hex');
 execute 'set local role anon';bad:=false;begin perform public.evzon_submit_application(p,sig);exception when others then bad:=sqlerrm like '%refer yourself%';end;execute 'reset role';if not bad then raise exception 'FAIL self referral';end if;
 -- Only admins can verify milestones or change reward amounts.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',partner,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 bad:=false;begin perform public.evzon_command('referral',jsonb_build_object('id',rid));exception when others then bad:=sqlerrm like '%EVZON_FORBIDDEN%';end;if not bad then raise exception 'FAIL partner milestone permissions';end if;
 execute 'reset role';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',aid,'role','authenticated')::text,true);
 milestones:=jsonb_build_object('id',rid,'stage','Training','training_complete',false,'assessment_passed',true,'training_started_on',hire-7,'training_days_completed',6,'training_completed_on','','hired_on','','first_month_completed_on','','reason','Training progress reviewed');
 execute 'set local role authenticated';
 result:=public.evzon_command('referral',milestones);
 bad:=false;begin perform public.evzon_command('referral',milestones||jsonb_build_object('training_complete',true,'training_completed_on',hire-1));exception when others then bad:=sqlerrm like '%training days%';end;if not bad then raise exception 'FAIL six training days';end if;
 execute 'reset role';
 if exists(select 1 from public.evzon_rewards where referral_id=rid and amount<>0) then raise exception 'FAIL early training earnings';end if;
 milestones:=milestones||jsonb_build_object('stage','Training Completed','training_days_completed',7,'training_complete',true,'training_completed_on',hire-1);
 execute 'set local role authenticated';result:=public.evzon_command('referral',milestones);execute 'reset role';
 select id into training_reward from public.evzon_rewards where referral_id=rid and kind='Training' and amount=20 and status='Pending review' and worker_id is null;
 if training_reward is null then raise exception 'FAIL training reward before hiring';end if;
 execute 'set local role authenticated';bad:=false;begin perform public.evzon_command('reward',jsonb_build_object('id',training_reward,'status','Approved'));exception when others then bad:=sqlerrm like '%partner account%';end;execute 'reset role';if not bad then raise exception 'FAIL unapproved partner payout';end if;
 -- Admin approval opens tracking; training reward remains $20.
 update public.evzon_profiles set status='Approved' where id in (partner,other);
 select state into s from public.evzon_workspace where id;
 s:=jsonb_set(s,'{workers}',coalesce(s->'workers','[]')||jsonb_build_array(jsonb_build_object('id','qa-worker-'||req,'status','Active','name','QA worker')));
 update public.evzon_workspace set state=s where id;
 update public.evzon_referrals set worker_id='qa-worker-'||req where id=rid;
 milestones:=milestones||jsonb_build_object('hired_on',hire,'stage','Active');
 execute 'set local role authenticated';
 result:=public.evzon_command('referral',milestones);
 bad:=false;begin perform public.evzon_command('referral',milestones||jsonb_build_object('first_month_completed_on',(hire+interval '1 month')::date-1));exception when others then bad:=sqlerrm like '%full working month%';end;if not bad then raise exception 'FAIL first month early';end if;
 execute 'reset role';
 if exists(select 1 from public.evzon_rewards where referral_id=rid and kind='First month' and amount<>0) then raise exception 'FAIL elapsed time alone earns month reward';end if;
 milestones:=milestones||jsonb_build_object('stage','First Month Completed','first_month_completed_on',(hire+interval '1 month')::date);
 execute 'set local role authenticated';
 result:=public.evzon_command('referral',milestones);result:=public.evzon_command('refresh','{}');result:=public.evzon_command('refresh','{}');
 execute 'reset role';
 select id into month_reward from public.evzon_rewards where referral_id=rid and kind='First month' and amount=30 and status='Pending review';
 if month_reward is null or (select sum(amount) from public.evzon_rewards where referral_id=rid)<>50 or (select count(*) from public.evzon_rewards where referral_id=rid)<>2 then raise exception 'FAIL exact $50 / idempotent milestones';end if;
 if exists(select 1 from public.evzon_rewards where referral_id=rid and worker_id is null) then raise exception 'FAIL worker cost attribution after hiring';end if;
 -- Public offer changes prospectively, while this referral keeps $20 + $30.
 select to_jsonb(c) into cfg from public.evzon_referral_config c where id;
 execute 'set local role authenticated';perform public.evzon_command('config',cfg||'{"training_bonus":25,"training_days":8,"first_month_bonus":35}'::jsonb);execute 'reset role';
 if (select sum(amount) from public.evzon_rewards where referral_id=rid)<>50 or (select terms->>'training_bonus' from public.evzon_referrals where id=rid)<>'20' then raise exception 'FAIL terms locked';end if;
 -- Paying is explicit, approved, referenced and idempotent.
 execute 'set local role authenticated';
 bad:=false;begin perform public.evzon_command('reward',jsonb_build_object('id',training_reward,'status','Paid','payment_reference','test'));exception when others then bad:=sqlerrm like '%Approve the reward%';end;if not bad then raise exception 'FAIL approval before pay';end if;
 perform public.evzon_command('reward',jsonb_build_object('id',training_reward,'status','Approved'));
 perform public.evzon_command('reward',jsonb_build_object('id',month_reward,'status','Approved'));
 bad:=false;begin perform public.evzon_command('reward',jsonb_build_object('id',training_reward,'status','Paid','payment_reference',''));exception when others then bad:=sqlerrm like '%payment reference%';end;if not bad then raise exception 'FAIL required payment reference';end if;
 perform public.evzon_command('reward',jsonb_build_object('id',training_reward,'status','Paid','payment_reference','QA-TRAINING'));
 perform public.evzon_command('reward',jsonb_build_object('id',training_reward,'status','Paid','payment_reference','QA-TRAINING'));
 execute 'reset role';
 if (select count(*) from evzon_private.payouts where reward_id=training_reward)<>1 then raise exception 'FAIL duplicate payout';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',partner,'role','authenticated')::text,true);
 execute 'set local role authenticated';result:=public.evzon_portal();
 if not exists(select 1 from jsonb_array_elements(result->'referrals') r where r->>'id'=rid::text) or jsonb_array_length(result->'contacts')<>0 then raise exception 'FAIL partner tracking / contact privacy';end if;
 execute 'reset role';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other,'role','authenticated')::text,true);
 execute 'set local role authenticated';result:=public.evzon_portal();
 if exists(select 1 from jsonb_array_elements(result->'referrals') r where r->>'id'=rid::text) or exists(select 1 from public.evzon_rewards where referral_id=rid) then raise exception 'FAIL partner isolation';end if;
 execute 'reset role';
 perform set_config('evzon.referral_program_test','PASS: unique codes, pending verified links, case-insensitive attribution, forged beneficiary ignored, duplicate attribution, unverified/suspended/self-referral rejection, private resources, admin-only milestones, six vs seven days, pre-hire $20, verified first month $30, no duplicate rewards, immutable terms, approved referenced idempotent payouts, partner privacy',true);
end $test$;
select current_setting('evzon.referral_program_test') as result;
rollback;

