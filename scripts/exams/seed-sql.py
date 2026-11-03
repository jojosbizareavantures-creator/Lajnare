"""Emit a small, repeatable question-bank import for an authenticated database owner.

Usage: python scripts/exams/seed-sql.py --batch 0 [--batch-size 10]
Run validate-bank.py first. Apply each emitted SQL batch with the database tool.
This script never changes guides and never places answer keys in the web bundle.
"""
from pathlib import Path
import argparse,json

root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--batch',type=int,required=True)
parser.add_argument('--batch-size',type=int,default=10)
args=parser.parse_args()
assert args.batch>=0 and 1<=args.batch_size<=25
questions=sorted([q for p in (root/'content/exams').glob('practice-*.json') for q in json.loads(p.read_text())],key=lambda q:q['id'])
batch=questions[args.batch*args.batch_size:(args.batch+1)*args.batch_size]
assert batch,'No questions in this batch'
payload=json.dumps(batch,ensure_ascii=False,separators=(',',':'))
assert '$bank$' not in payload
print("""begin;
create temporary table exam_seed_batch (like evzon_private.exam_questions including defaults) on commit drop;
insert into exam_seed_batch(id,test_key,unit_id,prompt,options,correct,source_anchor,explanation)
select id,test_key,unit_id,prompt,options,correct,source_anchor,explanation
from jsonb_to_recordset($bank$"""+payload+"""$bank$::jsonb) as q(id text,test_key text,unit_id text,prompt jsonb,options jsonb,correct text,source_anchor text,explanation jsonb);
do $$ begin
 if exists(select 1 from exam_seed_batch q left join evzon_private.training_units u on u.id=q.unit_id where u.id is null or not u.published or strpos(u.body,q.source_anchor)=0) then
  raise exception 'Source guide mismatch: question bank was not saved';
 end if;
end $$;
insert into evzon_private.exam_questions(id,test_key,unit_id,prompt,options,correct,source_anchor,explanation)
select id,test_key,unit_id,prompt,options,correct,source_anchor,explanation from exam_seed_batch
on conflict(id) do update set test_key=excluded.test_key,unit_id=excluded.unit_id,prompt=excluded.prompt,options=excluded.options,correct=excluded.correct,source_anchor=excluded.source_anchor,explanation=excluded.explanation;
commit;
select count(*) as total_questions from evzon_private.exam_questions;
""")
