"""Validate bilingual assessments against the existing curriculum, without changing it."""
from pathlib import Path
import json,collections,re,hashlib
root=Path(__file__).resolve().parents[2]
units={u['id']:u for u in json.loads((root/'content/training/curriculum.json').read_text())}
questions=[q for p in sorted((root/'content/exams').glob('practice-*.json')) for q in json.loads(p.read_text())]
expected={f'practice-{n}':25 for n in range(1,6)}|{'final':30}
assert dict(collections.Counter(q['test_key'] for q in questions))==expected
assert len({q['id'] for q in questions})==155
for lang in ('en','mk'):
 assert len({q['prompt'][lang].strip().casefold() for q in questions})==155,'Duplicate questions'
for q in questions:
 assert q['unit_id'] in units
 assert len(q['source_anchor'])>=12 and q['source_anchor'] in units[q['unit_id']]['body'],q['id']
 assert len(q['options'])==4 and {o['id'] for o in q['options']}==set('abcd'),q['id']
 assert q['correct'] in 'abcd' and len(q['correct'])==1
 for lang in ('en','mk'):
  assert q['prompt'][lang].strip() and q['explanation'][lang].strip(),q['id']
  assert len({o[lang].strip().casefold() for o in q['options']})==4,q['id']
  assert all(o[lang].strip() for o in q['options']),q['id']
  if lang=='mk':assert re.search('[А-Яа-яЃѓЌќЏџ]',q['prompt'][lang]),q['id']
manifest={'questions':155,'tests':expected,'languages':['en','mk'],'source':'content/training/curriculum.json','source_sha256':hashlib.sha256((root/'content/training/curriculum.json').read_bytes()).hexdigest(),'practice_rule':'Complete all five tests, regardless of score.','final_rule':'One admin authorization per attempt; scoring and feedback happen on the server.','source_units':sorted({q['unit_id'] for q in questions})}
(root/'content/exams/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Verified 155 unique bilingual questions: five practices of 25, one final of 30, four choices each, and exact supporting guide excerpts. Guide files unchanged.')
