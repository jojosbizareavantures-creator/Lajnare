"""Generate a guarded, atomic data-only update for the private training tables."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[2]
folder=root/'content/training'
course=json.loads((folder/'curriculum.json').read_text())
manifest=json.loads((folder/'course-manifest.json').read_text())
base=set(manifest['base_ids'])
records=[]
for u in course:
 records.append({**u,'expected_md5':hashlib.md5(u['body'].encode()).hexdigest(),'existing':u['id'] in base})
payload=json.dumps(records,ensure_ascii=False)
assert '$course$' not in payload
sql="""begin;
select pg_advisory_xact_lock(782541);
create temporary table course_release on commit drop as
select * from jsonb_to_recordset($course$"""+payload+"""$course$::jsonb) as x(
 id text,day int,section text,title text,title_mk text,summary text,body text,body_mk text,
 note text,assets jsonb,position int,minutes int,published boolean,revision int,source text,
 expected_md5 text,existing boolean);
do $guard$ begin
 if exists(select 1 from course_release r left join evzon_private.training_units u using(id)
   where r.existing and (u.id is null or md5(u.body) is distinct from r.expected_md5 or u.revision<>r.revision
   or (u.body_mk<>'' and u.body_mk<>r.body_mk)))
 then raise exception 'Training content changed since preparation; no changes applied';end if;
 if exists(select 1 from course_release r join evzon_private.training_units u using(id) where not r.existing
   and (u.source<>r.source or md5(u.body)<>r.expected_md5 or u.body_mk<>r.body_mk))
 then raise exception 'Supplement ID conflicts with an existing chapter';end if;
end $guard$;
-- Translation and placement only: retain the English text, publication, revisions and read records.
update evzon_private.training_units u
 set title_mk=r.title_mk,body_mk=r.body_mk,position=r.position,updated_at=now()
 from course_release r where r.existing and u.id=r.id;
-- New chapters stay in draft until the matching frontend has deployed.
insert into evzon_private.training_units
 (id,day,section,title,title_mk,summary,body,body_mk,note,assets,position,minutes,published,revision,source)
select id,day,section,title,title_mk,summary,body,body_mk,note,assets,position,minutes,false,revision,source
from course_release where not existing
on conflict(id) do nothing;
select count(*) as chapters,count(*) filter(where body_mk<>'' and title_mk<>'') as translated,
 sum(jsonb_array_length(assets)) as original_images from evzon_private.training_units;
commit;
"""
target=root/'scripts/training/releases/2026-10-25-bilingual.sql'
target.parent.mkdir(parents=True,exist_ok=True);target.write_text(sql)
print(str(target),len(sql.encode()),'bytes')
