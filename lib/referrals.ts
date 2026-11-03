import {n,sum,type Row} from './finance';
import type {ReferralOffer} from './referral-program';
import type {Profile} from './cloud-contract';
export type Terms={program_version?:string;training_bonus?:number;training_days?:number;first_month_bonus?:number;hire_bonus:number;retention_bonus:number;retention_days:number;commission_rate:number;commission_months:number;require_collected:boolean};
export type Referral={id:string;referrer_id:string;candidate_name:string;worker_id:string|null;source:string;stage:string;training_started_on?:string|null;training_days_completed?:number;training_completed_on?:string|null;first_month_completed_on?:string|null;training_complete:boolean;assessment_passed:boolean;hired_on:string|null;worker_status:string;active_days:number;terms:Terms;reason:string;created_at:string;updated_at:string};
export type Reward={id:string;referral_id:string;referrer_id:string;worker_id:string|null;kind:'Hire'|'Retention'|'Commission'|'Training'|'First month';period:string;amount:number;status:string;explanation:string;terms:Terms;earned_at:string|null;approved_at:string|null;paid_at:string|null;payment_reference:string;reason:string};
export type Portal={profile:Profile;config:Terms&ReferralOffer&{resources:string};profiles:Profile[];referrals:Referral[];rewards:Reward[];events:{id:string;referrer_id:string;referral_id:string;message:string;created_at:string}[];contacts:{referral_id:string;email:string;phone:string;notes:string}[];periods:{worker_id:string;period:string;revenue:number;compensation:number}[];audit:any[]};
export const stages=['Submitted','Under Review','Interview','Training','Training Completed','Hired','Active','30-Day Milestone Completed','First Month Completed','Rejected','Withdrawn'];
export const earnedStatuses=['Pending review','Approved','Payable','Paid'];
export const isEarned=(r:{status:string})=>earnedStatuses.includes(r.status);
// The beneficiary is stored on the reward. Reassigning a referral never moves historical earnings.
export function referrerPayoutRows(p:Portal,rewards:Reward[]=p.rewards){
 const ids=new Set([...p.profiles.filter(x=>x.role==='REFERRER').map(x=>x.id),...rewards.map(x=>x.referrer_id)]);
 return [...ids].map(id=>{
  const profile=p.profiles.find(x=>x.id===id),rows=rewards.filter(x=>x.referrer_id===id);
  const amount=(status:string)=>Math.round(sum(rows.filter(x=>x.status===status),x=>n(x.amount))*100)/100;
  const pending=amount('Pending review'),approved=amount('Approved'),payable=amount('Payable'),paid=amount('Paid');
  return {id,name:profile?.name||'Historical referrer',email:profile?.email||'',preference:profile?.payout_preference||'',status:profile?.status||'Unavailable',pending,approved,payable,paid,approvedUnpaid:Math.round((approved+payable)*100)/100,earned:Math.round((pending+approved+payable+paid)*100)/100};
 }).sort((a,b)=>b.payable-a.payable||b.approvedUnpaid-a.approvedUnpaid||a.name.localeCompare(b.name));
}
export function commissionEnd(r:Referral){if(!r.hired_on)return '';const d=new Date(r.hired_on+'T12:00:00Z');d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()+r.terms.commission_months);d.setUTCDate(0);return d.toISOString().slice(0,10);}
export function referralStats(referrals:Referral[],rewards:Reward[]){const earned=rewards.filter(isEarned),hires=referrals.filter(r=>!!r.hired_on&&r.training_complete&&(r.terms.program_version==='milestones_v2'||r.assessment_passed)&&!!r.worker_id&&r.worker_status!=='Training');return {submitted:referrals.length,pipeline:referrals.filter(r=>!r.hired_on&&!['Rejected','Withdrawn'].includes(r.stage)).length,training:referrals.filter(r=>r.stage==='Training').length,trained:referrals.filter(r=>r.training_complete).length,hires:hires.length,retained:hires.filter(r=>r.terms.program_version==='milestones_v2'?!!r.first_month_completed_on:r.active_days>=r.terms.retention_days).length,active:referrals.filter(r=>r.worker_status==='Active').length,bonuses:sum(earned.filter(r=>r.kind!=='Commission'),r=>n(r.amount)),commissions:sum(earned.filter(r=>r.kind==='Commission'),r=>n(r.amount)),pending:sum(rewards.filter(r=>r.status==='Pending review'),r=>n(r.amount)),approved:sum(rewards.filter(r=>['Approved','Payable'].includes(r.status)),r=>n(r.amount)),paid:sum(rewards.filter(r=>r.status==='Paid'),r=>n(r.amount)),earned:sum(earned,r=>n(r.amount))};}
export function rewardRows(rewards:Reward[]):Row[]{return rewards.map(r=>({id:r.id,worker:r.worker_id||'',referrer:r.referrer_id,kind:r.kind,period:r.period.slice(0,7),amount:n(r.amount),status:r.status,date:r.earned_at?.slice(0,10)||'',paidDate:r.paid_at?.slice(0,10)||'',reference:r.payment_reference,explanation:r.explanation}));}
export async function api<T=any>(url:string,body?:unknown,method='POST',options:{keepalive?:boolean}={}):Promise<T>{
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),30000);
 try{
  let res:Response;
  try{res=await fetch(url,{method:body===undefined?'GET':method,headers:body===undefined?undefined:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',signal:controller.signal,keepalive:options.keepalive});}
  catch{throw Error(controller.signal.aborted?'Connection timed out. Your changes have not been confirmed. Please retry.':'Connection lost. Your changes have not been confirmed. Please retry.');}
  const data:any=await res.json().catch(()=>({error:'Unexpected server response. Please try again.'}));
  if(!res.ok||data.error)throw Object.assign(Error(data.error||'Request failed.'),{status:res.status,code:data.code});return data;
 }finally{clearTimeout(timer);}
}
