import {test} from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {adminPath,adminSections,referrerSections,referrerPath,landingPages,canEnter,loginDestination,legacyEntry,referralTabs} from '../lib/navigation';
import {earningsDefaults,estimateEarnings} from '../lib/earnings';
import {AuthForm} from '../components/Auth';
import {Home} from '../components/marketing/Home';
import {HowItWorks} from '../components/marketing/HowItWorks';
import {Earnings} from '../components/marketing/Earnings';
import {Training} from '../components/marketing/Training';
import {Referrals} from '../components/marketing/Referrals';
import {FAQ,faqGroups} from '../components/marketing/FAQ';
const admin={role:'ADMIN',status:'Approved'} as const;
const referrer={role:'REFERRER',status:'Approved'} as const;
test('administrative views have real filesystem routes under their persistent layout',()=>{
 assert.equal(adminPath('overview'),'/adminpanel');
 for(const section of adminSections)assert.ok(existsSync('app/(account)'+adminPath(section)+'/page.tsx'),section);
 assert.ok(existsSync('app/(account)/adminpanel/layout.tsx'));
 for(const p of landingPages)assert.ok(existsSync('app'+p.href+'/page.tsx'),p.href);
});
test('access gate permits only the right role and approval state',()=>{
 assert.ok(canEnter(admin,'ADMIN'));assert.ok(!canEnter(referrer,'ADMIN'));
 assert.ok(!canEnter(null,'ADMIN'));assert.ok(!canEnter({...admin,status:'Pending'},'ADMIN'));
 assert.ok(!canEnter({...admin,status:'Suspended'},'ADMIN'));
 assert.ok(canEnter({...referrer,status:'Pending'},'REFERRER'));
 assert.ok(!canEnter({...referrer,status:'Suspended'},'REFERRER'));
 assert.ok(!canEnter(admin,'REFERRER'));
});
test('login preserves known deep links only for the matching role',()=>{
 for(const section of adminSections)assert.equal(loginDestination(admin,adminPath(section)),adminPath(section));
 for(const section of referrerSections)assert.equal(loginDestination(referrer,referrerPath(section)),referrerPath(section));
 for(const section of Object.keys(referralTabs))assert.equal(loginDestination(admin,'/adminpanel/referrals/'+section),'/adminpanel/referrals/'+section);
 assert.equal(loginDestination(referrer,'/adminpanel/workers'),'/referrer');
 assert.equal(loginDestination(admin,'/referrer/earnings'),'/adminpanel');
});
test('login rejects external, protocol-relative, traversal and unregistered destinations',()=>{
 for(const next of ['https://example.invalid','//example.invalid','javascript:alert(1)','/adminpanel/../../api/auth','/adminpanel/not-real','/adminpanel?next=//example.invalid',null])assert.equal(loginDestination(admin,next),'/adminpanel');
});
test('old root reset links still reach the new dedicated recovery route',()=>{
 assert.equal(legacyEntry({}),'/landing');assert.equal(legacyEntry({recovery:'1'}),'/reset-password');assert.equal(legacyEntry({auth_error:'1'}),'/login?auth_error=1');
});
test('public earnings use a worker salary, not company agency revenue',()=>{
 const v=estimateEarnings(earningsDefaults);assert.equal(v.monthly,500);assert.equal(v.annual,6000);assert.equal(v.scheduledHours,208);assert.equal(v.effectiveHourly,500/208);assert.equal(v.weekly,6000/52);
});
test('bonus and base changes recalculate all earning projections',()=>{
 const v=estimateEarnings({...earningsDefaults,salary:700,bonus:125});assert.equal(v.monthly,825);assert.equal(v.annual,9900);assert.equal(v.effectiveHourly,825/208);
});
test('hours affect only the fixed salary hourly comparison, with safe zero handling',()=>{
 const v=estimateEarnings({...earningsDefaults,hours:4});assert.equal(v.monthly,500);assert.equal(v.scheduledHours,104);
 const zero=estimateEarnings({salary:0,bonus:0,hours:0,days:0});assert.equal(zero.monthly,0);assert.equal(zero.effectiveHourly,0);assert.equal(zero.annual,0);
 for(const salary of [NaN,Infinity,-1])assert.throws(()=>estimateEarnings({...earningsDefaults,salary}));
});
for(const [name,View] of [['Home',Home],['How it works',HowItWorks],['Earnings',Earnings],['Training',Training],['Referrals',Referrals],['FAQ',FAQ]] as const)test('public page renders complete content: '+name,()=>{
 const html=renderToStaticMarkup(<View/>);assert.equal((html.match(/<h1/g)||[]).length,1);assert.ok(html.length>2000);assert.ok(!html.includes('NaN'));assert.ok(!html.includes('Total agency revenue'));assert.ok(!html.includes('Stefan'));
 const hrefs=[...html.matchAll(/href="([^"]+)"/g)].map(x=>x[1]);assert.ok(hrefs.length>0);for(const href of hrefs)assert.ok(href.startsWith('/')||href.startsWith('#'),href);
});
test('earnings planner presents exact numeric controls and explicit non-guarantee',()=>{
 const html=renderToStaticMarkup(<Earnings/>);assert.equal((html.match(/type="range"/g)||[]).length,4);assert.equal((html.match(/type="number"/g)||[]).length,4);
 for(const t of ['$500.00','$6,000.00','208','not an offer or guaranteed earnings','Reset earnings example','before deductions'])assert.ok(html.toLowerCase().includes(t.toLowerCase()),t);
});
test('FAQ uses native accessible disclosure controls with complete answers',()=>{
 const html=renderToStaticMarkup(<FAQ/>),count=faqGroups.reduce((n,g)=>n+g.items.length,0);assert.equal((html.match(/<details/g)||[]).length,count);assert.equal((html.match(/<summary/g)||[]).length,count);assert.ok(html.includes('OnlyFans and Fanvue'));assert.ok(!html.includes('Agencies pay Evzon'));
});
test('authentication screens have individual URL links and distinguish referral registration',()=>{
 const login=renderToStaticMarkup(<AuthForm refresh={async()=>{}}/>);assert.ok(login.includes('href="/forgot-password"'));assert.ok(login.includes('href="/register"'));assert.ok(login.includes('href="/landing"'));
 const signup=renderToStaticMarkup(<AuthForm mode="signup" refresh={async()=>{}}/>);assert.ok(signup.includes('Create referrer account'));assert.ok(signup.includes('href="/apply"'));assert.ok(!signup.includes('value="ADMIN"'));assert.ok(signup.includes('aria-label="Language"'));
 const reset=renderToStaticMarkup(<AuthForm mode="reset" refresh={async()=>{}}/>);assert.ok(reset.includes('Send reset email'));assert.ok(!reset.includes('type="password"'));
});

test('first-month salary stays fixed while future pay changes the year-one scenario',()=>{
 const result=estimateEarnings({...earningsDefaults,salary:700,bonus:125});
 assert.equal(result.firstYear,500+11*825);
 assert.notEqual(result.firstYear,result.annual);
 assert.equal(estimateEarnings({...earningsDefaults,salary:0,bonus:0}).firstYear,500);
});
test('home has no salary graphic or amount; salary and training explain the first month and growth',()=>{
 const home=renderToStaticMarkup(<Home/>);assert.ok(!home.includes('earnings-float'));assert.ok(!home.includes('$500'));assert.ok(!home.includes('SALARY EXAMPLE'));
 for(const View of [Earnings,Training]){const html=renderToStaticMarkup(<View/>);assert.ok(html.includes('Your first month of work at Evzon is paid at $500.'));assert.ok(html.includes('If you are improving, you can earn more.'));assert.ok(html.includes('no automatic or fixed future amount'));}
 const faq=renderToStaticMarkup(<FAQ/>);assert.ok(faq.includes('paid at $500'));assert.ok(faq.includes('Is a raise automatic'));
});
test('job and training pages explain duties, shifts, assessment and equipment requirements',()=>{
 const job=renderToStaticMarkup(<HowItWorks/>);for(const text of ['Subscriber conversations','Sales support','What happens during a shift?','Complete the handover','A PC or laptop'])assert.ok(job.includes(text),text);
 const training=renderToStaticMarkup(<Training/>);for(const text of ['Communication fundamentals','Apply feedback','Complete the assessment','Training arrangements','first month of work'])assert.ok(training.includes(text),text);
});
import {MarketingShell} from '../components/marketing/MarketingShell';
test('every public navigation, CTA and guide shortcut points to a page or a real section',()=>{
 const pages=new Map([['/landing',Home],['/landing/how-it-works',HowItWorks],['/landing/earnings',Earnings],['/landing/training',Training],['/landing/referrals',Referrals],['/landing/faq',FAQ]].map(([path,View])=>[String(path),renderToStaticMarkup(<MarketingShell>{React.createElement(View as typeof Home)}</MarketingShell>)]));
 let links=0;
 for(const [path,html] of pages){for(const match of html.matchAll(/href="([^"]*)"/g)){
  const href=match[1];assert.ok(href&&!href.startsWith('javascript:'),'Non-empty safe link');const target=new URL(href,'https://evzon.example'+path);assert.equal(target.origin,'https://evzon.example');
  const rendered=pages.get(target.pathname);assert.ok(rendered||existsSync('app'+target.pathname+'/page.tsx')||existsSync('app/(account)'+target.pathname+'/page.tsx'),'Missing target: '+target.pathname);
  if(target.hash)assert.ok(rendered?.includes('id="'+target.hash.slice(1)+'"'),'Missing section: '+target.href);
  links++;
 }}
 assert.ok(links>=100);
});
