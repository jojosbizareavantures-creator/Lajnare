'use client';
import {useState} from 'react';
import {Wallet} from 'lucide-react';
import {useI18n} from './I18n';
import {referrerPayoutRows,type Portal,type Reward} from '@/lib/referrals';
import {sum} from '@/lib/finance';
import {Card,Metric,Table,Export,Button,money,currencyCol,Badge} from './ui';
import {Earnings} from './ReferralViews';
export function ReferrerPayouts({p,onReward}:{p:Portal;onReward:(r:Reward)=>void}){
 const {t:tr}=useI18n(),[referrer,sr]=useState(''),[month,sm]=useState('');
 const all=referrerPayoutRows(p),rewards=p.rewards.filter(r=>(!month||r.period.slice(0,7)===month)&&(!referrer||r.referrer_id===referrer));
 const rows=referrerPayoutRows(p,rewards).filter(r=>!referrer||r.id===referrer);
 return <section className="referrer-payouts">
  <Card title="Who needs to be paid?" sub="Amounts below follow each reward’s review and payment status. Select a referrer to inspect their rewards." action={<Export name="referrer-payout-summary" rows={rows.map(r=>({referrer_id:r.id,referrer:r.name,email:r.email,payout_preference:r.preference,earning_month:month||'All time',pending_review:r.pending,approved_not_payable:r.approved,ready_to_pay:r.payable,approved_unpaid:r.approvedUnpaid,already_paid:r.paid}))}/>}>
   <div className="report-filters payout-filters"><label>{tr('Referrer')}<select value={referrer} onChange={e=>sr(e.target.value)}><option value="">{tr('All referrers')}</option>{all.map(r=><option key={r.id} value={r.id}>{r.name} · {r.email||r.id}</option>)}</select></label><label>{tr('Earning month')}<input type="month" value={month} onChange={e=>sm(e.target.value)}/></label><Button onClick={()=>{sr('');sm('');}} disabled={!referrer&&!month}>{tr('Clear filters')}</Button></div>
   <p className="subtle">{tr(month?'Filtered by the month the reward was earned, not the date it was paid.':'All-time rewards and recorded payments.')}</p>
   <div className="metrics four compact-metrics"><Metric label="Ready to pay" value={money(sum(rows,r=>r.payable))} note="Payable rewards awaiting payment" good icon={<Wallet size={17}/>}/><Metric label="Approved, not yet payable" value={money(sum(rows,r=>r.approved))} note="Check outstanding payment conditions"/><Metric label="Pending review" value={money(sum(rows,r=>r.pending))} note="Not yet approved for payment"/><Metric label="Already paid" value={money(sum(rows,r=>r.paid))} note="Recorded external payments"/></div>
   <Table rows={rows} cols={[{key:'name',label:'Referrer',render:r=><div><b>{r.name}</b><small className="cell-note">{r.email}</small></div>},{key:'preference',label:'Payout preference',render:r=>r.preference||tr('Not provided')},currencyCol('pending','Pending review'),currencyCol('approved','Approved, not yet payable'),{key:'payable',label:'Ready to pay',render:r=><Badge tone={r.payable>0?'green':''}>{money(r.payable)}</Badge>},currencyCol('approvedUnpaid','Total approved unpaid'),currencyCol('paid','Already paid')]} extra={r=><button className="text-button" onClick={()=>{sr(r.id);document.getElementById('referrer-reward-details')?.scrollIntoView({block:'start'});}}>{tr('View rewards')}</button>} empty="Referrers will appear here once they register"/>
   <div className="info-banner">{tr('Ready to pay includes only Payable rewards. Total approved unpaid combines Approved and Payable rewards. Pending review is shown separately. Mark a reward Paid only after sending the payment and recording its reference.')}</div>
  </Card>
  <div id="referrer-reward-details"><Earnings p={{...p,rewards}} admin onReward={onReward}/></div>
 </section>;
}
