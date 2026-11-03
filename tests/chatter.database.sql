begin;
-- Include draft chapters in this rollback-only verification of the next release.
update evzon_private.training_units set published=true;
do $$
#variable_conflict use_variable
declare admin_id uuid:=gen_random_uuid(); chatter_id uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid(); forged_id uuid:=gen_random_uuid(); localday date:=(now() at time zone 'Europe/Skopje')::date; result jsonb; v_id uuid; before_count int; d int; count_rows int; u record; training jsonb;
begin
 insert into auth.users(id,email,raw_user_meta_data) values(admin_id,admin_id||'@chatter-test.invalid','{"name":"Portal test administrator"}');
 update public.evzon_profiles set role='ADMIN',status='Approved' where id=admin_id;
 update public.evzon_workspace set state=jsonb_set(state,'{workers}',(state->'workers')||jsonb_build_array(jsonb_build_object('id','TEST-CHATTER-ONE','name','Portal test','status','Training','payroll','Approved hours','salary',500,'rate',3,'hours',8,'days',26,'commission',5,'sales',0,'workerCommission',0,'bonus',0,'training',0,'other',0,'wageRate',3,'overtimeRate',4.5,'agency','','contract','','start',localday,'notes',''),jsonb_build_object('id','TEST-CHATTER-TWO','name','Other portal test','status','Training','payroll','Monthly salary')));
 -- Reproduce the Auth API's insert followed by trusted metadata attachment.
 insert into auth.users(id,email,encrypted_password,raw_user_meta_data) values(chatter_id,chatter_id||'@chatter-test.invalid','old-hash','{"name":"Portal test chatter"}');
 update auth.users set raw_app_meta_data=jsonb_build_object('evzon_role','CHATTER','worker_id','TEST-CHATTER-ONE','training_start',localday,'created_by',admin_id) where id=chatter_id;
 if not exists(select 1 from public.evzon_profiles where id=chatter_id and role='CHATTER' and status='Approved') then raise exception 'FAIL delayed chatter provisioning';end if;
 update auth.users set raw_app_meta_data=raw_app_meta_data where id=chatter_id;
 if (select count(*) from public.evzon_chatter_accounts where id=chatter_id)<>1 then raise exception 'FAIL provisioning not idempotent';end if;
 insert into auth.users(id,email,encrypted_password,raw_user_meta_data,raw_app_meta_data) values(other_id,other_id||'@chatter-test.invalid','old-hash','{"name":"Other test chatter"}',jsonb_build_object('evzon_role','CHATTER','worker_id','TEST-CHATTER-TWO','training_start',localday,'created_by',admin_id));
 insert into auth.users(id,email,raw_user_meta_data) values(forged_id,forged_id||'@chatter-test.invalid','{"name":"Forged role test","evzon_role":"CHATTER","role":"CHATTER"}');
 if (select role from public.evzon_profiles where id=forged_id)<>'REFERRER' then raise exception 'FAIL public signup role';end if;
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 result:=public.evzon_chatter_portal();
 if jsonb_array_length(result->'accounts')<>1 or result->'accounts'->0->>'id'<>chatter_id::text or result->'worker' ? 'rate' then raise exception 'FAIL data isolation';end if;
 begin perform public.evzon_portal();raise exception 'FAIL referral authorization';exception when raise_exception then if SQLERRM not like 'EVZON_FORBIDDEN%' then raise;end if;end;
 begin perform public.evzon_chatter_command('password-set');raise exception 'FAIL temporary password bypass';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 update auth.users set encrypted_password='changed-hash' where id=chatter_id;
 perform public.evzon_chatter_command('password-set');
 -- A future training start still blocks material 1, even though materials are self-paced.
 update public.evzon_chatter_accounts set training_start=localday+1 where id=chatter_id;
 if evzon_private.training_day_access(1) then raise exception 'FAIL future start content access';end if;
 begin perform public.evzon_chatter_command('submit-day','{"day":1}');raise exception 'FAIL future start submission';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 update public.evzon_chatter_accounts set training_start=localday where id=chatter_id;
 begin perform public.evzon_chatter_command('clock-in');raise exception 'FAIL early clock-in';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 update public.evzon_chatter_lessons set published=false where day=1;
 begin perform public.evzon_chatter_command('submit-day','{"day":1}');raise exception 'FAIL unpublished lesson';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 begin perform public.evzon_chatter_command('account',jsonb_build_object('chatter_id',other_id,'status','Suspended'));raise exception 'FAIL chatter admin action';exception when raise_exception then if SQLERRM not like 'EVZON_FORBIDDEN%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 for d in 1..4 loop perform public.evzon_chatter_command('lesson',jsonb_build_object('day',d,'title','Test lesson','content','Test study content','published',true));end loop;
 perform public.evzon_chatter_command('exam-config','{"pass_score":80,"max_attempts":3,"exam_enabled":true,"discord_url":"","questions":[{"id":"q1","question":"Test question","options":["Correct","Wrong","Wrong 2","Wrong 3"],"correct":0}]}');
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 training:=public.evzon_training_portal();
 if jsonb_array_length(training->'units')<>(select count(*) from evzon_private.training_units) then raise exception 'FAIL curriculum count';end if;
 if exists(select 1 from jsonb_array_elements(training->'units') x where (x->>'day')::int>1 and (x->>'body'<>'' or x->>'body_mk'<>'' or jsonb_array_length(x->'assets')>0)) then raise exception 'FAIL future lesson leak';end if;
 if public.evzon_training_asset('ppv1.png') then raise exception 'FAIL future image access';end if;
 begin perform public.evzon_training_command('read','{"id":"pitch-examples","revision":2}');raise exception 'FAIL future chapter completion';exception when raise_exception then if SQLERRM not like 'EVZON_FORBIDDEN%' then raise;end if;end;
 begin perform public.evzon_chatter_command('submit-day','{"day":1}');raise exception 'FAIL unread day submitted';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 perform public.evzon_training_command('read','{"id":"foundations","revision":2,"notes":"Test trainer question"}');
 perform public.evzon_training_command('read','{"id":"foundations","revision":2,"notes":"Updated test trainer question"}');
 if (select count(*) from evzon_private.training_reads r where r.chatter_id=chatter_id and unit_id='foundations')<>1 then raise exception 'FAIL duplicate study record';end if;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 begin perform public.evzon_training_portal();raise exception 'FAIL temporary password training access';exception when raise_exception then if SQLERRM not like 'EVZON_FORBIDDEN%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',forged_id::text,true);
 begin perform public.evzon_training_portal();raise exception 'FAIL referrer curriculum leak';exception when raise_exception then if SQLERRM not like 'EVZON_FORBIDDEN%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 select * into u from evzon_private.training_units where id='foundations';
 perform public.evzon_training_command('edit-unit',to_jsonb(u)||jsonb_build_object('body',u.body||E'\n\nTest revision.'));
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 begin perform public.evzon_training_command('read','{"id":"foundations","revision":2}');raise exception 'FAIL stale chapter revision';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 for d in 1..4 loop
  perform set_config('request.jwt.claim.sub',chatter_id::text,true);
  for u in select * from evzon_private.training_units where day=d and published loop
   perform public.evzon_training_command('read',jsonb_build_object('id',u.id,'revision',u.revision,'notes','Reviewed in rollback verification'));
  end loop;
  if d=3 and not public.evzon_training_asset('ppv1.png') then raise exception 'FAIL unlocked image access';end if;
  perform public.evzon_chatter_command('submit-day',jsonb_build_object('day',d));
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.evzon_chatter_command('review-day',jsonb_build_object('chatter_id',chatter_id,'day',d,'status','Approved','feedback','Study reviewed'));
  perform set_config('request.jwt.claim.sub',chatter_id::text,true);
  if d<4 then
   training:=public.evzon_training_portal();
   if exists(select 1 from jsonb_array_elements(training->'units') x where (x->>'day')::int=d+1 and (not (x->>'unlocked')::boolean or x->>'body'='' or x->>'body_mk'='')) then raise exception 'FAIL next material remains locked after same-day approval';end if;
   begin perform public.evzon_chatter_command('submit-day',jsonb_build_object('day',d+1));raise exception 'FAIL next unread material submitted';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
   if d<3 and evzon_private.training_day_access(d+2) then raise exception 'FAIL skipped material approval';end if;
  end if;
 end loop;
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 -- The practice placeholder cannot be submitted and must not expose an unpublished exam.
 update public.evzon_chatter_lessons set published=false where day=5;
 if jsonb_array_length(public.evzon_chatter_portal()->'config'->'questions')<>0 then raise exception 'FAIL unpublished practice exam exposed';end if;
 begin perform public.evzon_chatter_command('submit-day','{"day":5}');raise exception 'FAIL empty practice submitted';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 begin perform public.evzon_chatter_command('exam','{"answers":{"q1":0}}');raise exception 'FAIL unpublished practice exam accepted';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_chatter_command('lesson','{"day":5,"title":"Practice fixture","content":"Rollback-only practice activity","published":true}');
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 result:=public.evzon_chatter_portal();
 if jsonb_array_length(result->'config'->'questions')<>1 then raise exception 'FAIL same-day exam access after four approved materials';end if;
 if result->'config'->'questions'->0 ? 'correct' then raise exception 'FAIL leaked exam key';end if;
 begin perform public.evzon_chatter_command('submit-day','{"day":5}');raise exception 'FAIL exam gate';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 perform public.evzon_chatter_command('exam','{"answers":{"q1":1}}');
 if exists(select 1 from public.evzon_chatter_accounts where id=chatter_id and hired_at is not null) then raise exception 'FAIL failed exam hired';end if;
 perform public.evzon_chatter_command('exam','{"answers":{"q1":0}}');
 if not exists(select 1 from public.evzon_chatter_accounts where id=chatter_id and hired_at is not null) then raise exception 'FAIL passed exam';end if;
 for d in 5..7 loop
  perform set_config('request.jwt.claim.sub',chatter_id::text,true);
  if d>=6 then
   begin perform public.evzon_chatter_command('submit-day',jsonb_build_object('day',d));raise exception 'FAIL early scheduled live stage';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
   update public.evzon_chatter_accounts set training_start=localday-d+1 where id=chatter_id;
  end if;
  for u in select * from evzon_private.training_units where day=d and published loop
   perform public.evzon_training_command('read',jsonb_build_object('id',u.id,'revision',u.revision,'notes','Reviewed in rollback verification'));
  end loop;
  if d=3 and not public.evzon_training_asset('ppv1.png') then raise exception 'FAIL unlocked image access';end if;
  perform public.evzon_chatter_command('submit-day',jsonb_build_object('day',d));
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  if d=7 then
   begin perform public.evzon_chatter_command('review-day',jsonb_build_object('chatter_id',chatter_id,'day',d,'status','Approved','feedback','Trial reviewed'));raise exception 'FAIL missing CEO review';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
  end if;
  perform public.evzon_chatter_command('review-day',jsonb_build_object('chatter_id',chatter_id,'day',d,'status','Approved','feedback','Observed training session','ceo_review',d=7));
 end loop;
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 if jsonb_array_length(public.evzon_training_portal()->'units')<>0 or public.evzon_training_asset('MM1.png') then raise exception 'FAIL graduate training visibility';end if;
 result:=public.evzon_chatter_portal();if jsonb_array_length(result->'lessons')<>0 or result->'worker'->>'status'<>'Active' then raise exception 'FAIL graduation';end if;
 perform public.evzon_chatter_command('clock-in','{"clock_in":"2000-01-01"}');
 begin perform public.evzon_chatter_command('clock-in');raise exception 'FAIL double clock-in';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 perform public.evzon_chatter_command('clock-out');
 select e.id into v_id from public.evzon_chatter_time e where e.chatter_id=(result->'profile'->>'id')::uuid order by clock_in desc limit 1;
 -- Set a completed two-hour fixture; the application itself only uses server timestamps.
 update public.evzon_chatter_time set clock_in=now()-interval '2 hours',clock_out=now() where id=v_id;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_chatter_command('attendance',jsonb_build_object('id',v_id,'status','Approved','regular_hours',2,'overtime_hours',0));
 begin perform public.evzon_chatter_command('attendance',jsonb_build_object('id',v_id,'status','Approved','regular_hours',2,'overtime_hours',0));raise exception 'FAIL repeated attendance approval';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 if (select count(*) from public.evzon_workspace,jsonb_array_elements(state->'shifts') x where x->>'attendanceId'=v_id::text)<>1 then raise exception 'FAIL duplicate payroll shift';end if;
 perform public.evzon_chatter_command('payout-create',jsonb_build_object('chatter_id',chatter_id,'period',date_trunc('month',localday)::date,'amount',500,'notes','Test salary'));
 select p.id into v_id from public.evzon_chatter_payouts p where p.chatter_id=(result->'profile'->>'id')::uuid order by created_at desc limit 1;
 perform public.evzon_chatter_command('payout-update',jsonb_build_object('id',v_id,'status','Paid','reference','TEST-ONLY'));
 begin perform public.evzon_chatter_command('payout-update',jsonb_build_object('id',v_id,'status','Paid','reference','TEST-ONLY'));raise exception 'FAIL duplicate payment';exception when raise_exception then if SQLERRM not like 'EVZON_INVALID:%' then raise;end if;end;
 if (select count(*) from public.evzon_workspace,jsonb_array_elements(state->'actualExpenses') x where x->>'chatterPayoutId'=v_id::text)<>1 then raise exception 'FAIL duplicate cash expense';end if;
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 execute 'set local role authenticated';
 select count(*) into count_rows from public.evzon_chatter_accounts;if count_rows<>1 then raise exception 'FAIL RLS account isolation';end if;
 select count(*) into count_rows from public.evzon_workspace;if count_rows<>0 then raise exception 'FAIL RLS workspace leak';end if;
 begin perform * from evzon_private.training_units;raise exception 'FAIL private curriculum grant';exception when insufficient_privilege then null;end;
 begin perform * from evzon_private.training_reads;raise exception 'FAIL private study records grant';exception when insufficient_privilege then null;end;
 begin perform * from evzon_private.chatter_config;raise exception 'FAIL exam config grant';exception when insufficient_privilege then null;end;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_chatter_command('account',jsonb_build_object('chatter_id',chatter_id,'status','Suspended'));
 update auth.users set raw_app_meta_data=raw_app_meta_data,email_confirmed_at=now() where id=chatter_id;
 if (select status from public.evzon_profiles where id=chatter_id)<>'Suspended' then raise exception 'FAIL metadata update restored suspended access';end if;
 perform set_config('request.jwt.claim.sub',chatter_id::text,true);
 begin perform public.evzon_chatter_portal();raise exception 'FAIL suspended access';exception when raise_exception then if SQLERRM not like 'EVZON_FORBIDDEN%' then raise;end if;end;

 -- An optional exam must not block the shadowing-only training plan.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_chatter_command('exam-config','{"pass_score":80,"max_attempts":3,"exam_enabled":false,"discord_url":"","questions":[]}');
 update public.evzon_chatter_accounts set training_start=localday-6 where id=other_id;
 update auth.users set encrypted_password='new-other-hash' where id=other_id;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 perform public.evzon_chatter_command('password-set');
 for d in 1..7 loop
  perform set_config('request.jwt.claim.sub',other_id::text,true);
  for u in select * from evzon_private.training_units where day=d and published loop
   perform public.evzon_training_command('read',jsonb_build_object('id',u.id,'revision',u.revision,'notes','Reviewed in rollback verification'));
  end loop;
  if d=3 and not public.evzon_training_asset('ppv1.png') then raise exception 'FAIL unlocked image access';end if;
  perform public.evzon_chatter_command('submit-day',jsonb_build_object('day',d));
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.evzon_chatter_command('review-day',jsonb_build_object('chatter_id',other_id,'day',d,'status','Approved','feedback','Reviewed training','ceo_review',d=7));
 end loop;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 result:=public.evzon_chatter_command('clock-in');
 v_id:=(result->'entries'->0->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_chatter_command('close-clock',jsonb_build_object('id',v_id,'notes','Forgot to clock out'));
 if not exists(select 1 from public.evzon_chatter_time where id=v_id and clock_out is not null and status='Pending') then raise exception 'FAIL forgotten clock review';end if;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 result:=public.evzon_chatter_portal();
 if jsonb_array_length(result->'lessons')<>0 or (result->'totals'->>'paid')::numeric<>0 then raise exception 'FAIL graduated portal isolation';end if;
 if has_function_privilege('anon','public.evzon_training_portal()','EXECUTE') or has_function_privilege('anon','public.evzon_training_asset(text)','EXECUTE') then raise exception 'FAIL anonymous training access';end if;
 if has_function_privilege('anon','public.evzon_chatter_portal()','EXECUTE') then raise exception 'FAIL anon portal access';end if;
end $$;
rollback;
select 'All chatter workflow and access-control checks passed. Test changes rolled back.' as result;

