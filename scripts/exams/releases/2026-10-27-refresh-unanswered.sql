-- Refresh only unanswered questions in running attempts after the bank release.
-- Submitted attempts, saved answers and the questions already answered are immutable.
-- Keep the existing question/option order and increment optimistic-lock versions.
begin;
select pg_advisory_xact_lock(782541);
create temporary table exam_copy_release_before on commit drop as
select id,to_jsonb(a) as record from evzon_private.exam_attempts a;

do $refresh$
declare attempt evzon_private.exam_attempts; revised jsonb;
begin
 for attempt in select * from evzon_private.exam_attempts where status='In progress' for update loop
  if exists(
   select 1 from jsonb_array_elements(attempt.questions) t(question)
   left join evzon_private.exam_questions q on q.id=t.question->>'id'
   left join evzon_private.training_units u on u.id=q.unit_id
   where not (attempt.answers ? (t.question->>'id'))
   and (q.id is null or q.test_key<>attempt.test_key or not u.published or strpos(u.body,q.source_anchor)=0)
  ) then raise exception 'An unanswered question no longer has a valid bank/source match'; end if;

  select jsonb_agg(case when attempt.answers ? (t.question->>'id') then t.question
   else to_jsonb(q)||jsonb_build_object(
    'options',(select jsonb_agg(fresh.option order by old.position)
      from jsonb_array_elements(t.question->'options') with ordinality old(option,position)
      join lateral jsonb_array_elements(q.options) fresh(option) on fresh.option->>'id'=old.option->>'id'),
    'source_title',u.title,'source_title_mk',u.title_mk,'source_day',u.day)
   end order by t.position) into revised
  from jsonb_array_elements(attempt.questions) with ordinality t(question,position)
  left join evzon_private.exam_questions q on q.id=t.question->>'id'
  left join evzon_private.training_units u on u.id=q.unit_id;

  if revised is distinct from attempt.questions then
   update evzon_private.exam_attempts set questions=revised,version=version+1 where id=attempt.id;
  end if;
 end loop;
end $refresh$;

do $verify$
declare snapshot record; current_record jsonb; before_question jsonb; after_question jsonb;
begin
 for snapshot in select * from exam_copy_release_before loop
  select to_jsonb(a) into current_record from evzon_private.exam_attempts a where a.id=snapshot.id;
  if current_record is null then raise exception 'An attempt was removed'; end if;
  if snapshot.record->>'status'='Submitted' then
   if current_record is distinct from snapshot.record then raise exception 'A submitted attempt changed'; end if;
   continue;
  end if;
  if current_record-'questions'-'version' is distinct from snapshot.record-'questions'-'version' then
   raise exception 'Saved answers or attempt metadata changed';
  end if;
  if jsonb_array_length(current_record->'questions')<>jsonb_array_length(snapshot.record->'questions') then
   raise exception 'Question count changed';
  end if;
  for before_question,after_question in
   select before_q.question,after_q.question
   from jsonb_array_elements(snapshot.record->'questions') with ordinality before_q(question,position)
   join jsonb_array_elements(current_record->'questions') with ordinality after_q(question,position) using(position)
  loop
   if before_question->>'id' is distinct from after_question->>'id' then raise exception 'Question order changed'; end if;
   if (snapshot.record->'answers') ? (before_question->>'id') then
    if before_question is distinct from after_question then raise exception 'An answered question changed'; end if;
   end if;
   if (select jsonb_agg(o->>'id' order by pos) from jsonb_array_elements(before_question->'options') with ordinality t(o,pos))
    is distinct from (select jsonb_agg(o->>'id' order by pos) from jsonb_array_elements(after_question->'options') with ordinality t(o,pos))
    then raise exception 'Option order changed'; end if;
  end loop;
 end loop;
end $verify$;
commit;
select count(*) filter(where status='In progress') as active_attempts,
 count(*) filter(where status='Submitted') as submitted_attempts
from evzon_private.exam_attempts;
