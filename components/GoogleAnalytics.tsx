'use client';
import {useEffect,useRef,useState} from 'react';
import Script from 'next/script';
import {usePathname} from 'next/navigation';
import {useI18n} from '@/components/I18n';
import {Button} from '@/components/ui';
import {PRODUCTION_ORIGIN} from '@/lib/site-config';
import {ANALYTICS_CONSENT_KEY,GA_MEASUREMENT_ID,analyticsConsent,analyticsPage,isAnalyticsPage,disableAnalytics,sendAnalyticsPage,type AnalyticsConsent,type AnalyticsHost} from '@/lib/analytics';

function clearAnalyticsCookies(){
 const domains=[location.hostname,location.hostname.replace(/^www\./,'')];
 for(const entry of document.cookie.split(';')){
  const name=entry.trim().split('=')[0];if(!/^_ga(?:_|$)/.test(name))continue;
  document.cookie=`${name}=; Max-Age=0; Path=/; SameSite=Lax; Secure`;
  for(const domain of new Set(domains))document.cookie=`${name}=; Max-Age=0; Path=/; Domain=${domain}; SameSite=Lax; Secure`;
 }
}
export function GoogleAnalytics(){
 const pathname=usePathname(),{t}=useI18n();
 const [ready,setReady]=useState(false),[consent,setConsent]=useState<AnalyticsConsent|null>(null),[editing,setEditing]=useState(false),[loadTag,setLoadTag]=useState(false),lastPage=useRef('');
 const publicPage=!!pathname&&isAnalyticsPage(pathname),id=GA_MEASUREMENT_ID;
 useEffect(()=>{
  try{setConsent(analyticsConsent(localStorage.getItem(ANALYTICS_CONSENT_KEY)));}catch{}
  setReady(true);
  const update=(event:StorageEvent)=>{if(event.key===ANALYTICS_CONSENT_KEY||event.key===null)setConsent(analyticsConsent(event.newValue));};
  addEventListener('storage',update);return()=>removeEventListener('storage',update);
 },[]);
 useEffect(()=>{
  if(!id)return;
  const host=window as unknown as AnalyticsHost,page=analyticsPage(location.href,PRODUCTION_ORIGIN,document.referrer);
  if(!ready||consent!=='granted'||!page){disableAnalytics(host,id);if(consent==='denied')clearAnalyticsCookies();lastPage.current='';return;}
  if(lastPage.current!==page.page_location){
   sendAnalyticsPage(host,id,page,consent);lastPage.current=page.page_location;
  }else host['ga-disable-'+id]=false;
  setLoadTag(true);
  return()=>disableAnalytics(host,id);
 },[pathname,consent,ready,id]);
 const choose=(next:AnalyticsConsent)=>{
  if(id&&next==='denied'){disableAnalytics(window as unknown as AnalyticsHost,id);clearAnalyticsCookies();}
  try{localStorage.setItem(ANALYTICS_CONSENT_KEY,next);}catch{}
  setConsent(next);setEditing(false);
 };
 if(!id||!publicPage)return null;
 return <>
  {loadTag&&consent==='granted'&&<Script id="evzon-google-analytics" src={`https://www.googletagmanager.com/gtag/js?id=${id}`} strategy="afterInteractive"/>}
  {ready&&(consent===null||editing)?<section className="analytics-consent" aria-label={t('Analytics preferences')}>
   <div><b>{t('Optional visit statistics')}</b><p>{t('Google Analytics helps us understand visits to our public pages. This is optional.')}</p></div>
   <div className="analytics-consent-actions"><Button small onClick={()=>choose('denied')}>{t('Decline analytics')}</Button><Button small primary onClick={()=>choose('granted')}>{t('Allow analytics')}</Button></div>
  </section>:ready&&<button type="button" className="analytics-preferences" onClick={()=>setEditing(true)}>{t('Analytics preferences')}</button>}
 </>;
}
