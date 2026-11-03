import {test} from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {canEnter,loginDestination,profileHome} from '../lib/navigation';
import {canStudy,trainingLockReason,trainingAvailableOn,nextTrainingStage,trainingStageLabel,shiftEnd,localMonth,type ChatterPortalData} from '../lib/chatter';
import {TrainingHub} from '../components/chatter/TrainingHub';
import {I18nProvider} from '../components/I18n';
const account={id:'chatter-1',worker_id:'W1',training_start:'2026-10-01',completed_at:null,hired_at:null,must_change_password:false,created_at:'2026-10-01',name:'Test learner',email:'learner@example.invalid',status:'Approved' as const};
const data:ChatterPortalData={profile:{...account,role:'CHATTER',code:'',payout_preference:''},accounts:[account],lessons:Array.from({length:7},(_,i)=>({day:i+1,title:'Lesson '+(i+1),title_mk:'Лекција '+(i+1),content:'Published guide',content_mk:'Објавен водич',published:true})),progress:[],config:{pass_score:80,max_attempts:3,exam_enabled:false,questions:[],discord_url:''},attempts:[],entries:[],payouts:[],announcements:[],worker:null,shifts:[],totals:{approved_due:0,paid:0,approved_month_hours:0},today:'2026-10-07',server_time:'2026-10-07T10:00:00Z'};
const progress=Array.from({length:4},(_,i)=>({id:'p'+i,chatter_id:account.id,day:i+1,status:'Approved' as const,feedback:'',submitted_at:null,approved_at:null}));
test('chatter deep links stay in their workspace and cannot grant admin or referral access',()=>{
 const p={role:'CHATTER',status:'Approved'} as const;
 assert.equal(profileHome(p),'/chatterportal');
 for(const path of ['/adminpanel','/referrer','//evil.invalid','/chatterportal/unknown'])assert.equal(loginDestination(p,path),'/chatterportal');
 assert.equal(loginDestination(p,'/chatterportal/payouts'),'/chatterportal/payouts');
 assert.ok(canEnter(p,'CHATTER'));assert.ok(!canEnter(p,'ADMIN'));assert.ok(!canEnter(p,'REFERRER'));
 assert.ok(!canEnter({...p,status:'Pending'},'CHATTER'));assert.ok(!canEnter({...p,status:'Suspended'},'CHATTER'));
});
test('materials unlock on the same calendar day after each previous approval',()=>{
 for(const stage of [1,2,3,4,5]){
  assert.ok(canStudy(stage,account,progress.slice(0,stage-1),'2026-10-01'));
  assert.ok(!canStudy(stage,account,progress.slice(0,stage-1),'2026-09-30'));
  if(stage>1){
   assert.equal(trainingLockReason(stage,account,progress.slice(0,stage-2),'2026-10-07'),'previous');
   assert.ok(!canStudy(stage,account,progress.map(p=>({...p,chatter_id:'someone-else'})),'2026-10-07'));
  }
 }
 assert.ok(!canStudy(2,account,[{...progress[0],status:'Submitted'}],'2026-10-01'));
 assert.ok(!canStudy(2,account,[{...progress[0],status:'Changes needed'}],'2026-10-01'));
 assert.ok(!canStudy(1,{...account,completed_at:'2026-10-07'},[],'2026-10-07'));
 for(const stage of [0,8,1.5,NaN])assert.ok(!canStudy(stage,account,progress,'2026-10-07'));
 assert.equal(nextTrainingStage(account.id,[progress[0],progress[2]]),2);
});
test('live shadowing and CEO trial retain their scheduled dates',()=>{
 const approved=Array.from({length:6},(_,i)=>({...progress[0],day:i+1}));
 assert.equal(trainingAvailableOn(5,account.training_start),'2026-10-01');
 assert.equal(trainingAvailableOn(6,account.training_start),'2026-10-06');
 assert.equal(trainingAvailableOn(7,account.training_start),'2026-10-07');
 assert.equal(trainingLockReason(6,account,approved,'2026-10-01'),'scheduled');
 assert.ok(canStudy(6,account,approved,'2026-10-06'));
 assert.ok(!canStudy(7,account,approved,'2026-10-06'));
 assert.ok(canStudy(7,account,approved,'2026-10-07'));
});
test('approved material 1 opens material 2 immediately with the renamed navigation',()=>{
 const html=renderToStaticMarkup(<TrainingHub data={{...data,today:'2026-10-01',progress:[progress[0]]}} account={account} busy={false} act={async()=>data}/>);
 assert.match(html,/Loading your chapters/);
 assert.doesNotMatch(html,/One step at a time/);
 for(const stage of [1,2,3,4])assert.match(html,new RegExp('Learning material '+stage));
 assert.match(html,/Practicing for exams/);
 assert.doesNotMatch(html,/>Day<.*[1-5]/);
 assert.equal(trainingStageLabel(5),'Practicing for exams');
});
test('published practice uses the new test hub and cannot bypass the final exam',()=>{
 const render=(published=true)=>renderToStaticMarkup(<TrainingHub data={{...data,progress,lessons:data.lessons.map(l=>l.day===5?{...l,published}:l)}} account={account} busy={false} act={async()=>data}/>);
 assert.match(render(),/Loading your practice tests/);
 assert.doesNotMatch(render(),/Request trainer review|Knowledge exam|Submit exam/);
 assert.match(render(false),/Exam practice is being prepared/);
 assert.doesNotMatch(render(false),/Request trainer review|Loading your practice tests/);
 const passed=renderToStaticMarkup(<TrainingHub data={{...data,progress}} account={{...account,hired_at:'2026-10-07'}} busy={false} act={async()=>data}/>);
 assert.match(passed,/Request trainer review/);
});
test('Macedonian labels name materials and exam preparation',()=>{
 const html=renderToStaticMarkup(<I18nProvider initialLanguage="mk"><TrainingHub data={{...data,progress,lessons:data.lessons.map(l=>({...l,published:false,content:''}))}} account={account} busy={false} act={async()=>data}/></I18nProvider>);
 assert.match(html,/Материјал за учење/);
 assert.match(html,/Подготовка за испити/);
 assert.match(html,/Подготовката за испити е во изработка/);
 assert.doesNotMatch(html,/Practicing for exams|Learning material/);
});
test('Macedonian training has a useful unpublished state without placeholder study content',()=>{
 const html=renderToStaticMarkup(<I18nProvider initialLanguage="mk"><TrainingHub data={{...data,lessons:data.lessons.map(l=>({...l,published:false,content:''}))}} account={account} busy={false} act={async()=>data}/></I18nProvider>);
 assert.match(html,/Вашиот водич се подготвува/);assert.doesNotMatch(html,/I have studied this guide/);
});
test('overnight shift ends and payroll month use Skopje time',()=>{
 assert.equal(shiftEnd({id:'s',start:'22:30',scheduled:8}),'06:30');
 assert.equal(shiftEnd({id:'s',start:'17:45',scheduled:6.5}),'00:15');
 assert.equal(localMonth('2026-09-30T22:30:00Z'),'2026-10');
});

