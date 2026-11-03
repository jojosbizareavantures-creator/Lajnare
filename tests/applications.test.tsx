import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {readFileSync} from 'node:fs';
import {ageOn,blankApplication,validateApplication,deviceInfo,signApplication,todayInSkopje} from '../lib/applications';
import {ApplicationForm} from '../components/ApplicationForm';
import {Applications} from '../components/Applications';
import {I18nProvider} from '../components/I18n';
import {Home} from '../components/marketing/Home';
import {HowItWorks} from '../components/marketing/HowItWorks';
import {Earnings} from '../components/marketing/Earnings';
import {Training} from '../components/marketing/Training';
import {Referrals} from '../components/marketing/Referrals';
import {FAQ} from '../components/marketing/FAQ';
import {MarketingShell} from '../components/marketing/MarketingShell';
import {readJson,checkOrigin} from '../lib/cloud-contract';
const today='2026-10-18';
const valid={...blankApplication,first_name:'Ana',last_name:'Test',country:'North Macedonia',city:'Skopje',date_of_birth:'2000-01-15',phone:'+389 70 123 456',email:'ana@example.invalid',gender:'F',equipment:'Laptop',adult:true,consent:true};
test('age boundaries use full calendar dates, including leap years and invalid dates',()=>{
 assert.equal(ageOn('2008-10-18',today),18);assert.equal(ageOn('2008-10-19',today),17);assert.equal(ageOn('2008-10-17',today),18);
 assert.equal(ageOn('2008-02-29','2026-02-28'),17);assert.equal(ageOn('2008-02-29','2026-03-01'),18);
 for(const date of ['2026-10-19','2008-02-30','not a date','1899-01-01','2000-13-01'])assert.equal(ageOn(date,today),null,date);
 assert.equal(todayInSkopje(new Date('2026-10-17T23:30:00Z')),'2026-10-18');
});
test('direct application needs no account or referral and only accepts defined fields',()=>{
 const result=validateApplication({...valid,first_name:' Ana ',email:' ANA@EXAMPLE.INVALID ',age:99,ip_address:'1.2.3.4',status:'Accepted',role:'ADMIN'},today);
 assert.equal(result.first_name,'Ana');assert.equal(result.email,'ana@example.invalid');assert.equal(result.code,'');
 for(const key of ['age','ip_address','status','role'])assert.ok(!(key in result));
 assert.equal(validateApplication({...valid,code:'abc123def456'},today).code,'ABC123DEF456');
});
test('mandatory details, age, PC/laptop and consent are enforced independently',()=>{
 for(const key of ['first_name','last_name','country','city','date_of_birth','phone','email','gender','equipment'])assert.throws(()=>validateApplication({...valid,[key]:''},today),key);
 for(const patch of [{date_of_birth:'2010-10-01',age:22},{date_of_birth:'2008-02-31'},{equipment:'Phone'},{gender:'other'},{adult:false},{consent:false},{phone:'123'},{phone:'1234567890123456'},{email:'not-an-email'},{message:'x'.repeat(2001)},{code:'bad'},{first_name:'a\u0000b'}])assert.throws(()=>validateApplication({...valid,...patch},today));
 for(const equipment of ['Desktop PC','Laptop','Desktop PC and laptop'])assert.equal(validateApplication({...valid,equipment},today).equipment,equipment);
});
test('device observations are coarse, bounded, and separate from claimed work equipment',()=>{
 const chrome=deviceInfo('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36');
 assert.equal(chrome.browser,'Chrome');assert.equal(chrome.os,'Windows');assert.equal(chrome.device_type,'Desktop / laptop');
 const mobile=deviceInfo('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile Safari/604.1');assert.equal(mobile.device_type,'Mobile');assert.equal(mobile.os,'iOS / iPadOS');
 assert.equal(deviceInfo('').device_type,'Unknown');assert.equal(deviceInfo('x'.repeat(2000)).user_agent.length,1000);
});
test('server HMAC matches Postgres-compatible SHA256, and rejects altered data by signature',async()=>{
 const payload=JSON.stringify({name:'Тест',ip:'192.0.2.1'}),secret='test-only-key';
 const signature=await signApplication(payload,secret);assert.equal(signature,createHmac('sha256',secret).update(payload).digest('hex'));
 assert.notEqual(await signApplication(payload+' ',secret),signature);
});
test('submission request limits and origin checks protect the public endpoint',async()=>{
 const request=(body:string,origin='https://evzon.example')=>new Request('https://evzon.example/api/apply',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body});
 assert.doesNotThrow(()=>checkOrigin(request('{}')));assert.throws(()=>checkOrigin(request('{}','https://other.example')));
 await assert.rejects(()=>readJson(request('x'.repeat(32001)),32000),/too large/);assert.deepEqual(await readJson(request('{"message":"Hello"}'),32000),{message:'Hello'});
});
test('application form renders every requested field, privacy details and a direct submit action',()=>{
 const html=renderToStaticMarkup(<ApplicationForm/>);
 for(const field of ['first_name','last_name','country','city','date_of_birth','phone','email','gender','equipment'])assert.ok(html.includes('name="'+field+'"'),field);
 for(const label of ['IP address','PC or laptop required','18+','Message / additional information','Referral code (optional)','Submit chatter application'])assert.ok(html.includes(label),label);
 assert.ok(!html.includes('type="password"'));assert.ok(!html.includes('value="Phone"'));assert.ok(html.includes('type="submit"'));
});
test('new public and admin screens are fully translated to Macedonian',()=>{
 for(const View of [<ApplicationForm/>,<Applications/>]){
  const html=renderToStaticMarkup(<I18nProvider initialLanguage="mk">{View}</I18nProvider>).replace(/<svg\b[\s\S]*?<\/svg>/g,'');
  const untranslated=[...html.matchAll(/>([^<>]+)</g)].map(x=>x[1].trim()).filter(x=>/[a-zA-Z]{3}/.test(x)&&!/[Ѐ-ӿ]/.test(x));assert.deepEqual(untranslated,[]);
 }
});
test('all public guides focus on the role without disclosing internal payments',()=>{
 for(const View of [Home,HowItWorks,Earnings,Training,Referrals,FAQ])for(const language of ['en','mk'] as const){
  const html=renderToStaticMarkup(<I18nProvider initialLanguage={language}><MarketingShell><View/></MarketingShell></I18nProvider>);
  assert.ok(!/agenc(?:y|ies)|worker contribution|company revenue|агенци(?:ја|и)|приходи на компанијата/i.test(html),View.name+' '+language);
  assert.ok(html.includes('href="/apply"'));assert.ok(html.includes(language==='en'?'Apply now':'Пријави се'));
 }
});
test('application reviews use authenticated admin identity and DB authorization',()=>{
 const route=readFileSync('app/api/applications/route.ts','utf8');assert.equal((route.match(/identity\(s.client,true\)/g)||[]).length,2);
 const schema=readFileSync('supabase/applications.sql','utf8');assert.ok(schema.includes('enable row level security'));assert.ok(schema.includes('auth.uid() is null or not evzon_private.is_admin()'));
});
