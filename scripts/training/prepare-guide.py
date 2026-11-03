"""Split the latest upload verbatim. Formatting and placement never rewrite the source."""
from pathlib import Path
import re,json,hashlib,sys
source=Path(sys.argv[1]);root=Path(__file__).resolve().parents[2]
text=source.read_text() # Universal newlines only; every supplied word and character is retained.
existing=root/'content/training/curriculum.json'
if existing.exists() and any(u.get('body_mk') or u.get('source')!=source.name for u in json.loads(existing.read_text())):
 raise SystemExit('The course has translations or supplements. Use compose-course.py to preserve them.')
markers=[
 ('foundations',1,'Foundations','The role and the shift routine','PART 1'),
 ('workspace',1,'Infloww','Workspace, access and the inbox','PART 2'),
 ('insights-notes',1,'Infloww','Fan insights and notes','4. Fan insights'),
 ('tools-library',1,'Infloww','Scripts, Vault Pro and Smart Lists','6. Scripts'),
 ('infloww-shift',1,'Infloww','Mass messages, statistics and etiquette','9. Mass messages'),
 ('flow-intro',2,'Conversation paths','Purpose and pacing','Conversation Flow 1.'),
 ('flow-opening',2,'Conversation paths','Steps 1–5 · Opening through the offer','# 3. STEP-BY-STEP'),
 ('flow-purchase',2,'Conversation paths','Steps 6–9 · Successful purchase','# 4. THE THREE'),
 ('flow-no-unlock',2,'Conversation paths','Steps 10–13 · No unlock','## STEP 10'),
 ('flow-no-pitch',2,'Conversation paths','Steps 14–20 · Aftercare and no pitch','## STEP 14'),
 ('flow-reference',2,'Conversation paths','Decision tree and quick reference','# 6. COMPLETE'),
 ('no-pitch-practice',2,'Customer care','When a customer will not buy','Conversation Flow 2.'),
 ('rapport-practice',2,'Customer care','Relationship building and checklist','## 6. RELATIONSHIP'),
 ('pitch-method',3,'PPV offers','How to sales pitch','3. How to Sales pitch:'),
 ('pitch-timing',3,'PPV offers','Timing and constructing the pitch','# MASTERING SALES PITCHES'),
 ('pitch-examples',3,'PPV offers','First, second and third sales pitches','### 7. First Sales'),
 ('aftercare',3,'PPV offers','Aftercare and the complete process','### 11. What to Do'),
 ('support-boundaries',4,'Difficult situations','Common scenarios · 1–5','Difficult situations, and answers:'),
 ('support-service',4,'Difficult situations','Common scenarios · 6–10','6. Fan is asking to move'),
 ('mass-messages',4,'Daily operations','Targeted mass messages','SOPO'),
 ('daily-offers',4,'Daily operations','Welcoming, pricing, customs and VIP','## 3. Catch and Hook'),
 ('records-retention',4,'Daily operations','Labels, refiltering and retention','## 7. Labeling'),
 ('daily-followups',4,'Daily operations','Tips, failed pitches and aftercare','## 10. Do Not Randomly'),
 ('shift-preparation',4,'Daily operations','Shift preparation and Fanvue','## 14. Preparing'),
 ('daily-checklist',4,'Daily operations','Daily workflow and core rules','## 17. Complete Daily')]
def asset(name,title,caption):return dict(name=name,title=title,caption=caption)
images={
'pitch-timing':[asset('ppv7.png','Transitioning into the PPV','Small-talk and transition reference slide.'),asset('ppv8.png','General transition strategies','A reference slide about the transition to a PPV sale.')],
'pitch-examples':[asset('ppv1.png','Sending the PPV','A slide about selecting content and personalizing captions.'),asset('ppv2.png','How to write PPVs','A source checklist for writing PPV messages.'),asset('ppv3.png','Caption examples · set one','Two supplied message examples.'),asset('ppv4.png','Caption examples · set two','Three supplied message examples.')],
'aftercare':[asset('ppv5.png','Engagement after the PPV','The supplied post-PPV engagement slide.'),asset('ppv6.png','Long-term fan retention','The supplied retention and notes slide.')],
'mass-messages':[asset('MM1.png','MM1 · Wordplay opener','An opener followed by three paired follow-up groups.'),asset('MM2.png','MM2 · Pop-culture opener','A pop-culture opening and its follow-ups.'),asset('MM3.png','MM3 · Secret-themed opener','A curiosity-led opening and follow-up sequence.'),asset('MM4.png','MM4 · Anecdote structure','An opening with labeled FU1–FU3 follow-ups.'),asset('MM5.png','MM5 · Recurring-theme sequence','Several follow-up paragraphs using one theme.'),asset('MM6.png','MM6 · Extended-metaphor sequence','An opening with labeled FU1–FU4 follow-ups.'),asset('MM7.png','MM7 · Preference-question opener','An opening question and follow-up sequence.')]
}
starts=[text.index(m[-1]) for m in markers]+[len(text)];assert starts==sorted(starts)
units=[]
for i,(id,day,section,title,marker) in enumerate(markers):
 body=text[starts[i]:starts[i+1]]
 units.append(dict(id=id,day=day,section=section,title=title,title_mk='',summary='',body=body,body_mk='',note='',assets=images.get(id,[]),position=i+1,minutes=max(2,round(len(body.split())/180)+len(images.get(id,[]))),published=True,revision=2,source=source.name))
assert ''.join(u['body'] for u in units)==text,'Any text alteration must fail the import.'
assert len([a for u in units for a in u['assets']])==15
(root/'content/training/curriculum.json').write_text(json.dumps(units,ensure_ascii=False,indent=2)+'\n')
manifest={'source':source.name,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'normalized_sha256':hashlib.sha256(text.encode()).hexdigest(),'verbatim':True,'units':len(units),'days':{str(d):[u['id'] for u in units if u['day']==d] for d in range(1,5)},'images':[{**a,'unit':u['id'],'day':u['day']} for u in units for a in u['assets']]}
(root/'content/training/source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Verified exact reconstruction:',len(text),'characters;',len(units),'chapters; 15 images.')
