import {test} from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {createDocumentNavigation,isPlainInternalClick,saveBeforeLeaving} from '../lib/document-navigation';
import {adminPath,adminSections,referrerPath,referrerSections,referralTabs,loginDestination} from '../lib/navigation';
import {WorkspaceLink,NavigationProvider} from '../components/Navigation';
import {JoinPurpose,referralPurpose,chatterPurpose} from '../components/JoinPurpose';
import {I18nProvider} from '../components/I18n';
import {api} from '../lib/referrals';

const click={button:0,defaultPrevented:false,metaKey:false,ctrlKey:false,shiftKey:false,altKey:false};
test('ordinary clicks can flush saves; new-tab, download and external links retain browser behavior',()=>{
 assert.equal(isPlainInternalClick(click,'/adminpanel/workers'),true);
 for(const value of [{...click,button:1},{...click,button:2},{...click,ctrlKey:true},{...click,metaKey:true},{...click,shiftKey:true},{...click,altKey:true},{...click,defaultPrevented:true}])assert.equal(isPlainInternalClick(value,'/adminpanel/workers'),false);
 for(const href of ['https://other.example/','//other.example/','#details',undefined])assert.equal(isPlainInternalClick(click,href),false);
 assert.equal(isPlainInternalClick(click,'/referrer','_blank'),false);
 assert.equal(isPlainInternalClick(click,'/report.csv',undefined,''),false);
});
test('admin, referral and nested payout destinations use document navigation',async()=>{
 const visited:string[]=[];const navigation=createDocumentNavigation(href=>visited.push(href));
 const paths=['/adminpanel',...adminSections.map(adminPath),'/referrer',...referrerSections.map(referrerPath),...Object.keys(referralTabs).map(tab=>'/adminpanel/referrals/'+tab)];
 for(const path of paths)assert.equal(await navigation.navigate(path),true);
 assert.deepEqual(visited,paths);
 const html=renderToStaticMarkup(<NavigationProvider>{paths.map(path=><WorkspaceLink key={path} href={path}>Open</WorkspaceLink>)}</NavigationProvider>);
 assert.equal((html.match(/<a /g)||[]).length,paths.length);
 for(const path of paths)assert.ok(html.includes('href="'+path+'"'));
});
test('a click waits for save acknowledgement and coalesces repeated clicks',async()=>{
 let release!:()=>void;const saved=new Promise<void>(resolve=>release=resolve);const events:string[]=[];
 const navigation=createDocumentNavigation(href=>events.push('visit '+href));
 navigation.register(async()=>{events.push('save');await saved;events.push('saved');});
 const first=navigation.navigate('/adminpanel/team'),second=navigation.navigate('/adminpanel/workers');
 assert.equal(first,second);await Promise.resolve();assert.deepEqual(events,['save']);
 release();assert.equal(await first,true);assert.deepEqual(events,['save','saved','visit /adminpanel/team']);
});
test('failed saves keep the page open and a later retry can navigate',async()=>{
 const states:{pending:boolean;error:string}[]=[];let visits=0;let shouldFail=true;
 const navigation=createDocumentNavigation(()=>visits++,state=>states.push(state));
 navigation.register(async()=>{if(shouldFail)throw Error('Save conflict');});
 assert.equal(await navigation.navigate('/adminpanel/expenses'),false);assert.equal(visits,0);assert.equal(states.at(-1)?.error,'Save conflict');
 shouldFail=false;assert.equal(await navigation.navigate('/adminpanel/expenses'),true);assert.equal(visits,1);assert.equal(states.at(-1)?.error,'');
});
test('a salary edit during an in-flight save is saved again before navigation',async()=>{
 let current=500,saved=0;const writes:number[]=[];
 const navigation=createDocumentNavigation(()=>assert.equal(saved,700));
 navigation.register(()=>saveBeforeLeaving(()=>current!==saved,async()=>{const snapshot=current;writes.push(snapshot);await Promise.resolve();if(snapshot===500)current=700;saved=snapshot;}));
 assert.equal(await navigation.navigate('/adminpanel/distribution'),true);assert.deepEqual(writes,[500,700]);
});
test('unchanged workspaces do not write; save failures never spin or discard changes',async()=>{
 let attempts=0;await saveBeforeLeaving(()=>false,async()=>{attempts++;});assert.equal(attempts,0);
 await assert.rejects(saveBeforeLeaving(()=>true,async()=>{attempts++;throw Error('Offline');}),/Offline/);assert.equal(attempts,1);
});
test('sign-in role redirects and logout use replace navigation',async()=>{
 const visited:[string,boolean][]=[];const navigation=createDocumentNavigation((href,replace)=>visited.push([href,replace]));
 await navigation.navigate(loginDestination({role:'ADMIN'},'/adminpanel/team'),true);
 await navigation.navigate(loginDestination({role:'REFERRER'},'/adminpanel/team'),true);
 await navigation.navigate('/login',true);
 assert.deepEqual(visited,[['/adminpanel/team',true],['/referrer',true],['/login',true]]);
});
test('programmatic navigation rejects external and malformed destinations',async()=>{
 let visits=0;const navigation=createDocumentNavigation(()=>visits++);
 for(const path of ['//evil.example','https://evil.example','javascript:alert(1)','/\\evil.example','/login\n'])assert.equal(await navigation.navigate(path),false);
 assert.equal(visits,0);
});
test('unmounting the financial provider releases its save guard',async()=>{
 let saves=0;const navigation=createDocumentNavigation(()=>{}),release=navigation.register(()=>{saves++;});
 assert.equal(navigation.hasGuard(),true);release();assert.equal(navigation.hasGuard(),false);await navigation.navigate('/referrer');assert.equal(saves,0);
});
test('registration and application notices clearly distinguish roles in English and Macedonian',()=>{
 for(const language of ['en','mk'] as const){
  const referral=renderToStaticMarkup(<I18nProvider initialLanguage={language}><JoinPurpose kind="referral"/></I18nProvider>);
  const chatter=renderToStaticMarkup(<I18nProvider initialLanguage={language}><JoinPurpose kind="chatter"/></I18nProvider>);
  assert.ok(referral.includes('href="/apply"'));assert.ok(chatter.includes('href="/register"'));
  if(language==='en'){assert.ok(referral.includes(referralPurpose));assert.ok(chatter.includes(chatterPurpose));}
  else{assert.ok(referral.includes('Регистрацијата не е пријава за работа'));assert.ok(chatter.includes('Пријава за работа како четер'));assert.ok(chatter.includes('Пополнете го формуларот подолу'));assert.ok(!referral.includes(referralPurpose));}
 }
});
test('notification acknowledgements survive document navigation and API failures remain actionable',async()=>{
 const original=globalThis.fetch;const requests:RequestInit[]=[];
 try{
  globalThis.fetch=async(_url,options)=>{requests.push(options!);return Response.json({ok:true});};
  await api('/api/notifications',{ids:['one']},'PATCH',{keepalive:true});assert.equal(requests[0].keepalive,true);assert.ok(requests[0].signal);
  globalThis.fetch=async()=>new Response('<html>Unavailable</html>',{status:200});
  await assert.rejects(api('/api/auth'),/Unexpected server response/);
  globalThis.fetch=async()=>Response.json({error:'Another device saved newer changes.'},{status:409});
  await assert.rejects(api('/api/workspace',{},'PUT'),(error:unknown)=>(error as {status:number}).status===409);
 }finally{globalThis.fetch=original;}
});
