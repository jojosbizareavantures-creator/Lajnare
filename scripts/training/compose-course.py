"""Attach Macedonian translations and verbatim supplemental chapters without rewriting English."""
from pathlib import Path
import json,hashlib
from source_fidelity import restore_original,restore_formatting,apply_formatting,formatting_edits,corrections,clarifications,image_additions

root=Path(__file__).resolve().parents[2]
folder=root/'content/training'
manifest=json.loads((folder/'source-manifest.json').read_text())
base_ids=[id for day in manifest['days'].values() for id in day]
current={u['id']:u for u in json.loads((folder/'curriculum.json').read_text())}
base=[current[id] for id in base_ids]
assert hashlib.sha256(''.join(restore_original(u) for u in base).encode()).hexdigest()==manifest['normalized_sha256']
titles=[
'Улогата и рутината за смена','Работен простор, пристап и сандаче','Податоци и белешки за фановите',
'Скрипти, Vault Pro и Smart Lists','Масовни пораки, статистика и правила',
'Цел и темпо','Чекори 1–5 · Од почеток до понуда','Чекори 6–9 · Успешно купување',
'Чекори 10–13 · Без отклучување','Чекори 14–20 · Грижа и разговор без понуда',
'Дрво на одлуки и брз преглед','Кога клиентот не сака да купи','Градење однос и контролна листа',
'Како да направиш продажна понуда','Време и составување на понудата',
'Прва, втора и трета продажна понуда','Грижа по интеракцијата и целосниот процес',
'Чести ситуации · 1–5','Чести ситуации · 6–10','Целни масовни пораки',
'Пречекување, цени, нарачки и VIP','Ознаки, повторно филтрирање и задржување',
'Бакшиши, неуспешни понуди и грижа','Подготовка за смена и Fanvue','Дневен работен тек и основни правила']
for u,title in zip(base,titles):
 u['title_mk']=title
 u['body_mk']=(folder/'mk'/f"{u['id']}.md").read_text()

# Source order is kept in the manifest, even though lessons are placed by topic.
spec=[
 ('mm-catalog',4,'Daily operations','Mass messages · lists and message library','Масовни пораки · листи и библиотека со пораки','What are MassMessages','mass-messages'),
 ('fan-preferences',2,'Fan preferences','Fan interests and kink reference','Интереси и речник на фетиши','How to Identify','flow-intro'),
 ('fan-psychology',2,'Conversation paths','Attention, personalization and pacing','Внимание, персонализација и темпо','To work most effectively','fan-preferences'),
 ('ppv-momentum',3,'PPV offers','Follow-ups after sending a PPV','Дополнителни пораки по испраќање PPV','Rule: NEVER','ppv-caption-details'),
 ('fan-welcome',2,'Conversation paths','Welcoming fans and building comfort','Пречекување фанови и создавање удобност',' Welcoming fans properly','fan-psychology'),
 ('ppv-caption-details',3,'PPV offers','Specific moments and follow-up questions','Конкретни моменти и дополнителни прашања','Tease specific moments','pitch-examples'),
 ('session-finish',3,'PPV offers','Session endings and ongoing connection','Крај на сесијата и понатамошна поврзаност','KNOW WHEN TO STOP.','aftercare'),
 ('objections',3,'PPV offers','Responding to objections','Одговарање на приговори','Handling objections','session-finish'),
 ('code-games',3,'PPV offers','Codes, levels and access games','Кодови, нивоа и игри за пристап','on OnlyFans are sales tactics','objections')]
source=(folder/'supplement-2026-10-25.txt').read_text()
starts=[source.index(s[5]) for s in spec]+[len(source)]
assert starts==sorted(starts)
added=[]
for i,(id,day,section,title,mk,marker,after) in enumerate(spec):
 body=apply_formatting(source[starts[i]:starts[i+1]],id)
 added.append(dict(id=id,day=day,section=section,title=title,title_mk=mk,summary='',body=body,
  body_mk=(folder/'mk'/f'{id}.md').read_text(),note='',assets=[],position=0,
  minutes=max(2,round(len(body.split())/180)),published=True,revision=1,source='supplement-2026-10-25.txt'))
assert ''.join(restore_formatting(u) for u in added)==source
order=base_ids.copy()
pending=list(zip(spec,added))
while pending:
 before=len(pending)
 for pair in pending[:]:
  s,u=pair
  if s[6] in order: order.insert(order.index(s[6])+1,u['id']);pending.remove(pair)
 assert len(pending)<before
all_units={u['id']:u for u in base+added}
units=[all_units[id] for id in order]
for image in image_additions():
 unit=all_units[image['unit']]
 assert unit['day']==image['day']
 asset={key:image[key] for key in ('name','title','caption')}
 existing=[a for a in unit['assets'] if a['name']==image['name']]
 if existing: assert existing==[asset], 'Conflicting image metadata'
 else: unit['assets'].append(asset)
for i,u in enumerate(units):
 u['position']=(i+1)*10
 assert u['body_mk'].strip() and len(u['body_mk'])<=40000
assert [u['day'] for u in units]==sorted(u['day'] for u in units)
(folder/'curriculum.json').write_text(json.dumps(units,ensure_ascii=False,indent=2)+'\n')
release={'base_source':manifest['source'],'base_ids':base_ids,'base_sha256':manifest['normalized_sha256'],
 'supplement_source':'supplement-2026-10-25.txt','supplement_ids':[u['id'] for u in added],
 'supplement_sha256':hashlib.sha256(source.encode()).hexdigest(),'chapters':len(units),
 'languages':['en','mk'],'original_images':15,'additional_images':len(image_additions()),
 'image_additions':'image-additions.json' if image_additions() else None,'english_verbatim':not bool(corrections()),
 'user_corrections':'user-corrections.json' if corrections() else None,
 'formatting_edits':'formatting-edits.json' if formatting_edits() else None,
 'user_clarifications':'user-clarifications.json' if clarifications() else None,
 'published_base_sha256':hashlib.sha256(''.join(u['body'] for u in base).encode()).hexdigest(),
 'days':{str(d):[u['id'] for u in units if u['day']==d] for d in range(1,5)}}
(folder/'course-manifest.json').write_text(json.dumps(release,ensure_ascii=False,indent=2)+'\n')
print(f'{len(units)} bilingual chapters; supplied text preserved with recorded user corrections.')
