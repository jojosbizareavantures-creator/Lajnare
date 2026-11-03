export const ANALYTICS_CONSENT_KEY='evzon.analytics-consent.v1';
export const GA_MEASUREMENT_ID=measurementId(process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID??'G-15PY8YRJ87');
export type AnalyticsConsent='granted'|'denied';
export type AnalyticsPage={page_location:string;page_title:string;page_referrer:string};
export type AnalyticsHost={dataLayer?:unknown[];gtag?:(...args:unknown[])=>void;evzonAnalyticsStarted?:string;[key:string]:unknown};
const titles:Record<string,string>={
 '/landing':'EVZON · Home',
 '/landing/how-it-works':'EVZON · How it works',
 '/landing/earnings':'EVZON · Salaries and earnings',
 '/landing/training':'EVZON · Training',
 '/landing/referrals':'EVZON · Referral program',
 '/landing/faq':'EVZON · FAQ',
 '/apply':'EVZON · Chatter application'
};
export function measurementId(value:string):string|null{return /^G-[A-Z0-9]{6,20}$/.test(value)?value:null;}
export function analyticsConsent(value:string|null):AnalyticsConsent|null{return value==='granted'||value==='denied'?value:null;}
export function isAnalyticsPage(pathname:string):boolean{return Object.prototype.hasOwnProperty.call(titles,pathname.replace(/\/+$/,'')||'/');}
export function analyticsPage(href:string,productionOrigin:string,referrer=''):AnalyticsPage|null{
 try{
  const url=new URL(href),production=new URL(productionOrigin),path=url.pathname.replace(/\/+$/,'')||'/';
  if(production.protocol!=='https:'||url.protocol!=='https:'||!isAnalyticsPage(path))return null;
  if(url.origin!==production.origin&&url.origin!==`${production.protocol}//www.${production.host}`)return null;
  let page_referrer='';
  try{const r=new URL(referrer);if(['https:','http:'].includes(r.protocol))page_referrer=r.origin+'/';}catch{}
  // No query strings, fragments, referral codes, form values, or account paths.
  return {page_location:production.origin+path,page_title:titles[path],page_referrer};
 }catch{return null;}
}
export function disableAnalytics(host:AnalyticsHost,id:string){
 host['ga-disable-'+id]=true;
 if(host.evzonAnalyticsStarted===id)host.gtag?.('consent','update',{analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'});
}
export function sendAnalyticsPage(host:AnalyticsHost,id:string,page:AnalyticsPage,consent:AnalyticsConsent|null):boolean{
 if(!measurementId(id)||consent!=='granted'){disableAnalytics(host,id);return false;}
 host['ga-disable-'+id]=false;
 host.dataLayer??=[];
 host.gtag??=function(){host.dataLayer!.push(arguments);};
 if(host.evzonAnalyticsStarted!==id){
  host.gtag('consent','default',{analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'});
  host.gtag('set',{allow_google_signals:false,allow_ad_personalization_signals:false,ads_data_redaction:true,url_passthrough:false});
  host.gtag('js',new Date());host.evzonAnalyticsStarted=id;
 }
 host.gtag('consent','update',{analytics_storage:'granted',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'});
 host.gtag('set',page);
 host.gtag('config',id,{...page,send_page_view:false,allow_google_signals:false,allow_ad_personalization_signals:false,cookie_flags:'SameSite=Lax;Secure'});
 host.gtag('event','page_view',{...page,send_to:id});
 return true;
}
