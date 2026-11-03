import {test} from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {referralEstimate,firstMonthDue,validOffer} from '../lib/referral-program';
import {rememberReferral,rememberedReferral} from '../lib/referral-attribution';
import {initial,calculate,today} from '../lib/finance';
import {rewardRows,type Reward} from '../lib/referrals';
import {I18nProvider} from '../components/I18n';
import {translateText} from '../lib/i18n';
import {ReferralCalculator} from '../components/ReferralCalculator';
import {Referrals} from '../components/marketing/Referrals';
import {Home} from '../components/marketing/Home';
const offer={training_bonus:20,training_days:7,first_month_bonus:30};
test('specific milestone translations take precedence over generic day-count templates',()=>{
 assert.equal(translateText('After 7 completed training days','mk'),'По 7 завршени дена обука');
 assert.equal(translateText('After 14 completed training days','mk'),'По 14 завршени дена обука');
 assert.equal(translateText('Completed 7 training days, verified by an administrator.','mk'),'Завршени 7 дена обука, потврдени од администратор.');
});
test('calculator separates training completions from first-month completions',()=>{
 assert.deepEqual(referralEstimate(offer,1,1),{training:20,month:30,total:50});
 assert.deepEqual(referralEstimate(offer,10,10),{training:200,month:300,total:500});
 assert.deepEqual(referralEstimate(offer,10,4),{training:200,month:120,total:320});
 assert.deepEqual(referralEstimate(offer,0,0),{training:0,month:0,total:0});
 assert.equal(referralEstimate({...offer,training_bonus:21.25,first_month_bonus:30.10},3,2).total,123.95);
 for(const [training,month] of [[-1,0],[2,3],[NaN,0],[1.5,1],[10001,1]])assert.throws(()=>referralEstimate(offer,training,month));
 assert.equal(validOffer({...offer,training_days:7.5}),false);
});
test('first-month dates follow the same calendar-month rule as Postgres',()=>{
 assert.equal(firstMonthDue('2026-01-31'),'2026-02-28');
 assert.equal(firstMonthDue('2028-01-31'),'2028-02-29');
 assert.equal(firstMonthDue('2026-12-10'),'2027-01-10');
 assert.equal(firstMonthDue('2026-02-30'),'');
});
test('training before worker creation and first-month rewards cost $50 once; paying affects cash only',()=>{
 const state=structuredClone(initial),base=calculate(state);state.settings.cash=1000;
 const make=(id:string,kind:Reward['kind'],amount:number,worker:string|null):Reward=>({id,kind,amount,worker_id:worker,referral_id:'candidate',referrer_id:'partner',period:String(state.settings.period)+'-01',status:'Pending review',terms:{hire_bonus:20,retention_bonus:30,retention_days:30,commission_rate:0,commission_months:6,require_collected:true,program_version:'milestones_v2',...offer},explanation:'Verified',earned_at:today(),approved_at:null,paid_at:null,payment_reference:'',reason:''});
 const training=make('training','Training',20,null),month=make('month','First month',30,String(state.workers[0].id));
 state.referralRewards=rewardRows([training,month]);
 let result=calculate(state);assert.equal(result.net,base.net-50);assert.equal(result.referralCosts,50);assert.equal(result.cash,1000);
 assert.equal(result.workers[0].referralCost,30);
 training.worker_id=String(state.workers[0].id);training.status='Paid';training.paid_at=today();training.payment_reference='TRANSFER-1';
 state.referralRewards=rewardRows([training,month]);result=calculate(state);
 assert.equal(result.net,base.net-50);assert.equal(result.cash,980);assert.equal(result.workers[0].referralCost,50);
 assert.equal(result.payouts[0].distribution,(base.net-50)*.5);
});
test('public offer, calculator and two earning paths render in both languages without internal financial details',()=>{
 for(const lang of ['en','mk'] as const)for(const view of [<Referrals initialOffer={offer}/>,<Home offer={offer}/>,<ReferralCalculator offer={offer}/>]){
  const html=renderToStaticMarkup(<I18nProvider initialLanguage={lang}>{view}</I18nProvider>);
  assert.ok(!/agenc(?:y|ies)|worker contribution|company revenue|агенци(?:ја|и)/i.test(html));
  assert.ok(html.includes('$50')||html.includes('$500'));assert.ok(html.includes('href="/register"')||html.includes('href="/landing/referrals"'));
  if(lang==='mk'){
   const text=html.replace(/<svg\b[\s\S]*?<\/svg>/g,'');
   const untranslated=[...text.matchAll(/>([^<>]+)</g)].map(x=>x[1].trim()).filter(x=>/[A-Za-z]{3}/.test(x)&&!/[Ѐ-ӿ]/.test(x)&&!['EVZON','English','USD'].includes(x));
   assert.deepEqual(untranslated,[]);
  }
 }
 const html=renderToStaticMarkup(<ReferralCalculator offer={offer}/>);
 assert.ok(html.includes('type="range"'));assert.equal((html.match(/type="number"/g)||[]).length,2);
 assert.ok(html.includes('$200'));assert.ok(html.includes('$300'));assert.ok(html.includes('$500'));
});
test('referral hints survive guide navigation, expire and respect manual clearing',()=>{
 const saved=Object.getOwnPropertyDescriptor(globalThis,'localStorage'),data=new Map<string,string>();
 try{
  Object.defineProperty(globalThis,'localStorage',{configurable:true,value:{getItem:(k:string)=>data.get(k)||null,setItem:(k:string,v:string)=>data.set(k,v),removeItem:(k:string)=>data.delete(k)}});
  rememberReferral('abcdef123456',1000);assert.equal(rememberedReferral(1001),'ABCDEF123456');
  rememberReferral('123456ABCDEF',2000);assert.equal(rememberedReferral(2001),'123456ABCDEF');
  assert.equal(rememberedReferral(2000+30*24*60*60*1000),'');
  rememberReferral('ABCDEF123456');rememberReferral('');assert.equal(rememberedReferral(),'');
  rememberReferral('<script>');assert.equal(rememberedReferral(),'');
  Object.defineProperty(globalThis,'localStorage',{configurable:true,get(){throw Error('Unavailable');}});
  assert.doesNotThrow(()=>rememberReferral('ABCDEF123456'));assert.equal(rememberedReferral(),'');
 }finally{if(saved)Object.defineProperty(globalThis,'localStorage',saved);else Reflect.deleteProperty(globalThis,'localStorage');}
});
