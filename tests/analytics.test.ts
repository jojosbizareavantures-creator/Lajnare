import {test} from 'node:test';
import assert from 'node:assert/strict';
import {GA_MEASUREMENT_ID,analyticsConsent,analyticsPage,isAnalyticsPage,measurementId,sendAnalyticsPage,disableAnalytics,type AnalyticsHost} from '../lib/analytics';
const origin='https://evzonchatting.com';
test('GA4 uses the supplied measurement ID and rejects invalid tag input',()=>{
 assert.equal(GA_MEASUREMENT_ID,'G-15PY8YRJ87');
 for(const id of ['', 'G-', 'G-abc123','G-15PY8YRJ87<script>','UA-123'])assert.equal(measurementId(id),null);
 assert.equal(measurementId('G-15PY8YRJ87'),'G-15PY8YRJ87');
});
test('analytics only permits public pages on the production domain',()=>{
 for(const path of ['/landing','/landing/earnings','/landing/training','/apply'])assert.ok(analyticsPage(origin+path,origin));
 for(const path of ['/adminpanel','/adminpanel/applications','/chatterportal','/referrer','/login','/register','/auth/confirm','/api/workspace','/landing/private'])assert.equal(analyticsPage(origin+path,origin),null,path);
 for(const host of ['https://evzon.vercel.app','http://localhost:3000','https://evzonchatting.com.evil.invalid'])assert.equal(analyticsPage(host+'/landing',origin),null);
 assert.ok(analyticsPage('https://www.evzonchatting.com/landing',origin));
 assert.equal(isAnalyticsPage('/landing/'),true);
});
test('pageview payloads remove referral codes, tokens, query strings, fragments and referrer paths',()=>{
 const page=analyticsPage(origin+'/apply?ref=PRIVATE-CODE&email=person@example.com#token',origin,'https://search.example/results?email=private@example.com');
 assert.deepEqual(page,{page_location:origin+'/apply',page_title:'EVZON · Chatter application',page_referrer:'https://search.example/'});
 assert.equal(analyticsPage(origin+'/landing',origin,'not a url')?.page_referrer,'');
});
test('unknown or denied consent never queues a Google tag or pageview',()=>{
 for(const consent of [null,'denied'] as const){
  const host:AnalyticsHost={};assert.equal(sendAnalyticsPage(host,'G-15PY8YRJ87',analyticsPage(origin+'/landing',origin)!,consent),false);
  assert.equal(host.dataLayer,undefined);assert.equal(host['ga-disable-G-15PY8YRJ87'],true);
 }
 for(const value of [null,'yes','true',''])assert.equal(analyticsConsent(value),null);
});
test('consented visits disable automatic pageviews and advertising before one explicit pageview',()=>{
 const host:AnalyticsHost={},page=analyticsPage(origin+'/landing',origin)!;
 assert.ok(sendAnalyticsPage(host,'G-15PY8YRJ87',page,'granted'));
 const calls=host.dataLayer!.map(call=>Array.from(call as IArguments));assert.equal(calls[0][0],'consent');
 const config=calls.find(x=>x[0]==='config')![2] as Record<string,unknown>;
 assert.equal(config.send_page_view,false);assert.equal(config.allow_google_signals,false);assert.equal(config.allow_ad_personalization_signals,false);
 assert.equal(calls.filter(x=>x[0]==='event'&&x[1]==='page_view').length,1);
 const consent=calls.find(x=>x[0]==='consent'&&x[1]==='update')![2] as Record<string,unknown>;
 assert.equal(consent.analytics_storage,'granted');assert.equal(consent.ad_storage,'denied');assert.equal(consent.ad_user_data,'denied');
 disableAnalytics(host,'G-15PY8YRJ87');assert.equal(host['ga-disable-G-15PY8YRJ87'],true);
});
