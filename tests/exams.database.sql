-- Runs inside a transaction after the new schema; always roll back.
-- Synthetic fixtures are not saved and no account-creation emails are sent.
do $test$
#variable_conflict use_variable
declare
 admin_id uuid:=gen_random_uuid(); learner uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid(); referrer uuid:=gen_random_uuid(); today date:=(now() at time zone 'Europe/Skopje')::date;
 result jsonb; item jsonb; record_id uuid; previous_id uuid; first_order text; answers jsonb; test_number integer; j integer; denied boolean; n integer; before_total integer;
begin
 if has_table_privilege('authenticated','evzon_private.exam_questions','SELECT') or has_table_privilege('authenticated','evzon_private.exam_attempts','UPDATE') or has_table_privilege('anon','evzon_private.exam_permissions','SELECT') then raise exception 'FAIL private table grants';end if;
 if has_function_privilege('anon','public.evzon_exams_portal(uuid)','EXECUTE') or has_function_privilege('anon','public.evzon_exams_command(text,jsonb)','EXECUTE') then raise exception 'FAIL anonymous RPC access';end if;
 insert into auth.users(id,email,raw_user_meta_data) values(admin_id,admin_id||'@exam-fixture.invalid','{"name":"Exam fixture administrator"}'),(learner,learner||'@exam-fixture.invalid','{"name":"Exam fixture learner"}'),(other_id,other_id||'@exam-fixture.invalid','{"name":"Other fixture learner"}'),(referrer,referrer||'@exam-fixture.invalid','{"name":"Fixture referrer","role":"ADMIN"}');
 update public.evzon_profiles set role='ADMIN',status='Approved' where id=admin_id;
 update public.evzon_profiles set role='CHATTER',status='Approved' where id in (learner,other_id);
 insert into public.evzon_chatter_accounts(id,worker_id,training_start,must_change_password,created_by) values(learner,'EXAM-FIXTURE-'||learner,today,false,admin_id),(other_id,'EXAM-FIXTURE-'||other_id,today,false,admin_id);
 perform set_config('request.jwt.claim.sub',referrer::text,true);
 denied:=false;begin perform public.evzon_exams_portal();exception when raise_exception then denied:=SQLERRM like 'EVZON_FORBIDDEN%';end;if not denied then raise exception 'FAIL referrer access';end if;
 perform set_config('request.jwt.claim.sub',learner::text,true);
 denied:=false;begin perform public.evzon_exams_command('start','{"test_key":"practice-1"}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL early practice access';end if;
 insert into evzon_private.training_reads(chatter_id,unit_id,revision) select learner,id,revision from evzon_private.training_units where day<=4 and published;
 insert into public.evzon_chatter_progress(chatter_id,day,status,approved_at,approved_by) select learner,stage,'Approved',now(),admin_id from generate_series(1,4) as gs(stage);
 denied:=false;begin perform public.evzon_exams_command('authorize',jsonb_build_object('chatter_id',learner));exception when raise_exception then denied:=SQLERRM like 'EVZON_FORBIDDEN%';end;if not denied then raise exception 'FAIL self authorization';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 denied:=false;begin perform public.evzon_exams_command('authorize',jsonb_build_object('chatter_id',learner));exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL final authorized before completion';end if;
 for test_number in 1..5 loop
  perform set_config('request.jwt.claim.sub',learner::text,true);
  result:=public.evzon_exams_command('start',jsonb_build_object('test_key','practice-'||test_number));
  record_id:=(result->'attempt'->>'id')::uuid;
  if jsonb_array_length(result->'attempt'->'questions')<>25 then raise exception 'FAIL practice size';end if;
  if jsonb_array_length(result->'bank')<>0 or exists(select 1 from jsonb_array_elements(result->'attempt'->'questions') q where q ? 'correct' or q ? 'explanation' or q ? 'source_anchor') then raise exception 'FAIL answer leak';end if;
  if test_number=1 then
   select question_order into first_order from evzon_private.exam_attempts where id=record_id;previous_id:=record_id;
   if (public.evzon_exams_command('start','{"test_key":"practice-1"}')->'attempt'->>'id')::uuid<>record_id then raise exception 'FAIL duplicate start';end if;
   denied:=false;begin perform public.evzon_exams_command('start','{"test_key":"practice-2"}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL concurrent practice';end if;
   denied:=false;begin perform public.evzon_exams_command('submit',jsonb_build_object('id',record_id,'version',0,'answers','{}'::jsonb));exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL incomplete submission';end if;
   denied:=false;begin perform public.evzon_exams_command('save',jsonb_build_object('id',record_id,'version',0,'answers','{"forged":"a"}'::jsonb));exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL forged question';end if;
   item:=result->'attempt'->'questions'->0;
   result:=public.evzon_exams_command('save',jsonb_build_object('id',record_id,'version',0,'answers',jsonb_build_object(item->>'id','a')));
   if result->'attempt'->'answers'->>(item->>'id')<>'a' then raise exception 'FAIL saved answer';end if;
   if public.evzon_exams_portal()->'attempt'->>'id'<>record_id::text then raise exception 'FAIL resume';end if;
   denied:=false;begin perform public.evzon_exams_command('save',jsonb_build_object('id',record_id,'version',0,'answers','{}'::jsonb));exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL stale overwrite';end if;
   perform set_config('request.jwt.claim.sub',other_id::text,true);
   denied:=false;begin perform public.evzon_exams_portal(record_id);exception when raise_exception then denied:=SQLERRM like 'EVZON_FORBIDDEN%';end;if not denied then raise exception 'FAIL another learner attempt leak';end if;
   perform set_config('request.jwt.claim.sub',learner::text,true);
  end if;
  -- All wrong: completion must still advance eligibility.
  select jsonb_object_agg(q->>'id',(select o->>'id' from jsonb_array_elements(q->'options') o where o->>'id'<>q->>'correct' limit 1)) into answers from evzon_private.exam_attempts a cross join lateral jsonb_array_elements(a.questions) q where a.id=record_id;
  result:=public.evzon_exams_command('submit',jsonb_build_object('id',record_id,'version',(select version from evzon_private.exam_attempts where id=record_id),'answers',answers,'score',100));
  if (result->'attempt'->>'score')::numeric<>0 or result->'attempt'->'passed'<>'null'::jsonb then raise exception 'FAIL practice server scoring';end if;
  if jsonb_array_length(result->'summaries'->0->'practice_completed')<>test_number then raise exception 'FAIL practice completion depends on score';end if;
  if not (result->'attempt'->'questions'->0 ? 'correct') or not(result->'attempt'->'questions'->0 ? 'explanation') then raise exception 'FAIL submitted feedback';end if;
  if (public.evzon_exams_command('submit',jsonb_build_object('id',record_id,'version',0,'answers','{}'::jsonb))->'attempt'->>'id')::uuid<>record_id then raise exception 'FAIL submit idempotency';end if;
 end loop;
 if not (public.evzon_exams_portal()->'summaries'->0->'permission'='null'::jsonb) then raise exception 'FAIL automatic final permission';end if;
 denied:=false;begin perform public.evzon_exams_command('start','{"test_key":"final","screenshare_confirmed":true}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL unpermissioned final';end if;
 -- A new practice attempt receives a different order, while resume kept the old one.
 result:=public.evzon_exams_command('start','{"test_key":"practice-1"}');record_id:=(result->'attempt'->>'id')::uuid;
 if (select question_order from evzon_private.exam_attempts where id=record_id)=first_order then raise exception 'FAIL repeated question order';end if;
 select jsonb_object_agg(q->>'id',q->>'correct') into answers from evzon_private.exam_attempts a cross join lateral jsonb_array_elements(a.questions) q where a.id=record_id;
 perform public.evzon_exams_command('submit',jsonb_build_object('id',record_id,'version',0,'answers',answers));
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_exams_command('authorize',jsonb_build_object('chatter_id',learner,'note','Fixture supervised session'));
 perform public.evzon_exams_command('revoke',jsonb_build_object('chatter_id',learner));
 perform set_config('request.jwt.claim.sub',learner::text,true);
 denied:=false;begin perform public.evzon_exams_command('start','{"test_key":"final","screenshare_confirmed":true}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL revoked permission';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_exams_command('authorize',jsonb_build_object('chatter_id',learner));
 perform set_config('request.jwt.claim.sub',learner::text,true);
 denied:=false;begin perform public.evzon_exams_command('start','{"test_key":"final"}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL missing screenshare confirmation';end if;
 result:=public.evzon_exams_command('start','{"test_key":"final","screenshare_confirmed":true}');record_id:=(result->'attempt'->>'id')::uuid;
 if jsonb_array_length(result->'attempt'->'questions')<>30 or result->'summaries'->0->'permission'<>'null'::jsonb then raise exception 'FAIL final start grant consumption';end if;
 select jsonb_object_agg(q->>'id',(select o->>'id' from jsonb_array_elements(q->'options') o where o->>'id'<>q->>'correct' limit 1)) into answers from evzon_private.exam_attempts a cross join lateral jsonb_array_elements(a.questions) q where a.id=record_id;
 result:=public.evzon_exams_command('submit',jsonb_build_object('id',record_id,'version',0,'answers',answers));
 if (result->'attempt'->>'score')::numeric<>0 or (result->'attempt'->>'passed')::boolean or (result->'summaries'->0->>'final_passed')::boolean then raise exception 'FAIL failed final outcome';end if;
 if (select status from public.evzon_profiles where id=learner)<>'Approved' or (select hired_at from public.evzon_chatter_accounts where id=learner) is not null then raise exception 'FAIL final failure changes employment/access';end if;
 denied:=false;begin perform public.evzon_exams_command('start','{"test_key":"final","screenshare_confirmed":true}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL final grant reuse';end if;
 denied:=false;begin perform public.evzon_chatter_command('exam','{"answers":{}}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL legacy exam bypass';end if;
 denied:=false;begin perform public.evzon_chatter_command('submit-day','{"day":5}');exception when raise_exception then denied:=SQLERRM like 'EVZON_INVALID:%';end;if not denied then raise exception 'FAIL training pass gate';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 result:=public.evzon_exams_command('feedback',jsonb_build_object('id',record_id,'feedback','Study the referenced guides and discuss these mistakes before retrying.'));
 perform public.evzon_exams_command('authorize',jsonb_build_object('chatter_id',learner,'note','Second chance after feedback'));
 perform set_config('request.jwt.claim.sub',learner::text,true);
 if public.evzon_exams_portal(record_id)->'attempt'->>'feedback'='' then raise exception 'FAIL feedback visibility';end if;
 result:=public.evzon_exams_command('start','{"test_key":"final","screenshare_confirmed":true}');record_id:=(result->'attempt'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_exams_command('settings','{"pass_score":100,"discord_url":""}');
 perform set_config('request.jwt.claim.sub',learner::text,true);
 -- 24/30 at the captured 80% threshold passes even when future exams use 100%.
 select jsonb_object_agg(q->>'id',case when pos<=24 then q->>'correct' else (select o->>'id' from jsonb_array_elements(q->'options') o where o->>'id'<>q->>'correct' limit 1) end) into answers from evzon_private.exam_attempts a cross join lateral jsonb_array_elements(a.questions) with ordinality v(q,pos) where a.id=record_id;
 result:=public.evzon_exams_command('submit',jsonb_build_object('id',record_id,'version',0,'answers',answers));
 if (result->'attempt'->>'score')::numeric<>80 or not(result->'attempt'->>'passed')::boolean or (result->'attempt'->>'pass_score')::int<>80 then raise exception 'FAIL final threshold snapshot';end if;
 perform public.evzon_chatter_command('submit-day','{"day":5}');
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.evzon_chatter_command('review-day',jsonb_build_object('chatter_id',learner,'day',5,'status','Approved','feedback','Final result reviewed'));
 if (select status from public.evzon_chatter_progress where chatter_id=learner and day=5)<>'Approved' then raise exception 'FAIL stage progression';end if;
 if (select completed_at from public.evzon_chatter_accounts where id=learner) is not null then raise exception 'FAIL skipped shadowing and trial';end if;
 perform set_config('request.jwt.claim.sub',learner::text,true);
 if not evzon_private.training_day_access(1) then raise exception 'FAIL guide review access';end if;
 update public.evzon_profiles set status='Suspended' where id=learner;
 denied:=false;begin perform public.evzon_exams_portal();exception when raise_exception then denied:=SQLERRM like 'EVZON_FORBIDDEN%';end;if not denied then raise exception 'FAIL suspended access';end if;
 raise notice 'PASS: zero-score practice completion, saved/resumed attempts, one-use admin grants, shuffled orders, server scoring, privacy, feedback, retakes and training progression';
end $test$;
