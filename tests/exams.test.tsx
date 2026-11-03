import {test} from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {readFileSync} from 'node:fs';
import {finalEligibility,practiceTests,type ExamSummary,type ExamsData,type ExamAttempt} from '../lib/exams';
import {PracticeExams,TestRunner,AttemptReview} from '../components/chatter/PracticeExams';
import {ExamsAdmin} from '../components/chatter/ExamsAdmin';
import {I18nProvider} from '../components/I18n';
const s:ExamSummary={chatter_id:'test',name:'Learner',status:'Approved',unlocked:true,graduated:false,practice_completed:[],final_passed:false,permission:null,active_attempt:null};
const data:ExamsData={admin:false,settings:{pass_score:80},discord_url:'',summaries:[s],attempts:[],attempt:null,bank:[]};
const source=JSON.parse(readFileSync('content/exams/practice-one-two.json','utf8'));
const attempt:ExamAttempt={id:'attempt',chatter_id:'test',test_key:'practice-1',status:'Submitted',version:1,total:25,correct_count:0,score:0,passed:null,pass_score:80,started_at:'2026-10-26T10:00:00Z',submitted_at:'2026-10-26T10:05:00Z',feedback:'',reviewed_at:null,answers:Object.fromEntries(source.slice(0,25).map((q:any)=>[q.id,q.options.find((o:any)=>o.id!==q.correct).id])),questions:source.slice(0,25).map((q:any)=>({...q,source_title:'Workspace',source_title_mk:'Работен простор',source_day:1}))};
test('practice completion only controls eligibility, with separate authorization',()=>{
 assert.equal(finalEligibility(s),'practice');
 const done={...s,practice_completed:practiceTests.map(t=>t.key)};
 assert.equal(finalEligibility(done),'awaiting');
 assert.equal(finalEligibility({...done,permission:{id:'grant',note:'',granted_at:''}}),'authorized');
 assert.equal(finalEligibility({...done,unlocked:false}),'locked');
 assert.equal(finalEligibility({...done,final_passed:true}),'passed');
 assert.equal(finalEligibility({...done,practice_completed:['practice-1','practice-1','practice-2','practice-3','practice-4']}),'practice');
});
test('zero-score practice result says completed, not failed; final failure offers learning and a retry',()=>{
 const practice=renderToStaticMarkup(<AttemptReview attempt={attempt}/>);
 assert.match(practice,/Practice complete/);assert.match(practice,/regardless of your score/);assert.match(practice,/Why this is the answer/);assert.doesNotMatch(practice,/Final exam passed|Final exam failed/);
 const failed=renderToStaticMarkup(<AttemptReview attempt={{...attempt,test_key:'final',passed:false,total:30}}/>);
 assert.match(failed,/not a rejection/);assert.match(failed,/authorize another final attempt/);
});
test('learner hub explains practice-only completion and administrative final permission in both languages',()=>{
 for(const lang of ['en','mk'] as const){
  const html=renderToStaticMarkup(<I18nProvider initialLanguage={lang}><PracticeExams initialData={{...data,summaries:[{...s,practice_completed:practiceTests.map(t=>t.key)}]}} onPassed={()=>{}} onStudy={()=>{}}/></I18nProvider>);
  assert.match(html,lang==='en'?/Awaiting admin permission/:/Се чека дозвола од администраторот/);
  assert.match(html,lang==='en'?/no passing score/:/нема праг за положување/);
  assert.doesNotMatch(html,/>Start final exam</);
 }
});
test('test runner preserves shuffled option identity and gates incomplete submission',()=>{
 const q={...attempt.questions[0],correct:undefined,explanation:undefined,options:[...attempt.questions[0].options].reverse()};
 const html=renderToStaticMarkup(<TestRunner attempt={{...attempt,status:'In progress',questions:[q],answers:{},total:1}} busy={false} onSave={async()=>{}} onSubmit={async()=>{}}/>);
 assert.ok(html.indexOf(q.options[0].en)<html.indexOf(q.options[3].en));
 assert.match(html,/Answer every question/);assert.match(html,/disabled=""/);assert.doesNotMatch(html,/Why this is the answer/);
});
test('admin authorizes eligible zero-score practice completers and can review failed finals',()=>{
 const html=renderToStaticMarkup(<ExamsAdmin initialData={{...data,admin:true,summaries:[{...s,practice_completed:practiceTests.map(t=>t.key)}],attempts:[attempt]}}/>);
 assert.match(html,/Authorize one final attempt/);assert.match(html,/0\/25/);assert.match(html,/Completion/);
});
