'use client';
import {useState,useId} from 'react';
import {ArrowUpRight,Calculator} from 'lucide-react';
import {useI18n} from './I18n';
import {referralEstimate,type ReferralOffer} from '@/lib/referral-program';
export const referralMoney=(value:number)=>new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:2,minimumFractionDigits:0}).format(value);
export function ReferralCalculator({offer,partner=false}:{offer:ReferralOffer;partner?:boolean}){
 const {t}=useI18n(),id=useId(),[people,setPeople]=useState('10'),[month,setMonth]=useState<string|null>(null);
 const count=Number(people),completed=month===null?count:Number(month);
 let result:ReturnType<typeof referralEstimate>|null=null;
 try{if(people.trim()!==''&&(month===null||month.trim()!==''))result=referralEstimate(offer,count,completed);}catch{/* Retain invalid input and explain it below. */}
 const choose=(v:string)=>{setPeople(v);setMonth(null);};
 return <section className="referral-calculator" aria-labelledby={id+'-title'}>
  <div className="ref-calculator-inputs"><span className="marketing-kicker"><Calculator size={15}/>{t('YOUR CONNECTIONS, YOUR POTENTIAL')}</span><h2 id={id+'-title'}>{t('See what your referrals could earn.')}</h2><p>{t('Start with the people you know. Explore potential rewards when they complete the required milestones.')}</p>
   <div className="referral-presets" aria-label={t('Referral examples')}>{[1,5,10,20].map(v=><button key={v} type="button" aria-pressed={count===v} onClick={()=>choose(String(v))}>{v} {t(v===1?'person':'people')}</button>)}</div>
   <label className="referral-count-label" htmlFor={id+'-people'}>{t('People who complete training')}<input id={id+'-people'} type="number" inputMode="numeric" min={0} max={10000} step={1} value={people} onChange={e=>choose(e.target.value)}/></label>
   <input className="referral-range" aria-label={t('People who complete training slider')} type="range" min={0} max={Math.max(100,Number.isFinite(count)?Math.min(10000,count):100)} step={1} value={Number.isFinite(count)?count:0} onChange={e=>choose(e.target.value)}/>
   <label className="referral-count-label" htmlFor={id+'-month'}>{t('Of these, complete their first month')}<input id={id+'-month'} type="number" inputMode="numeric" min={0} max={Math.max(0,count)} step={1} value={month??people} onChange={e=>setMonth(e.target.value)}/></label>
   <p className="referral-fine-print">{t('Adjust the second number if fewer people reach the next milestone. All amounts are in USD.')}</p>
  </div>
  <div className="ref-calculator-result" aria-live="polite"><span className="marketing-kicker">{t('POTENTIAL REFERRAL REWARDS')}</span><strong className="ref-total">{result?referralMoney(result.total):'—'}</strong><span className="ref-total-caption">{t('One-time rewards across both milestones')}</span>
   {result?<div className="ref-calculation-lines"><div><span>{count} × {referralMoney(offer.training_bonus)}<small>{t('After verified training')}</small></span><b>{referralMoney(result.training)}</b></div><div><span>{completed} × {referralMoney(offer.first_month_bonus)}<small>{t('After the first working month')}</small></span><b>{referralMoney(result.month)}</b></div></div>:<p role="alert" className="negative">{t('Enter whole candidate counts from 0 to 10,000; month completions cannot exceed training completions.')}</p>}
   <p className="referral-fine-print">{t('This is an illustration, not guaranteed income or your earned balance. An application alone earns no reward. Each milestone must be completed and verified by Evzon.')}</p>
   <a className="marketing-button primary" href={partner?'/referrer/referrals':'/register'}>{t(partner?'Share your referral link':'Get my referral link')}<ArrowUpRight size={16}/></a>
  </div>
 </section>;
}
