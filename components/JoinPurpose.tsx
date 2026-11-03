'use client';
import {ArrowRight,MessageSquare,Users} from 'lucide-react';
import {useI18n} from './I18n';
import {PageLink} from './marketing/PublicUI';

export const referralPurpose='Create a referral partner account to recommend candidates and track eligible rewards. Registration does not apply you for a chatter position or guarantee employment.';
export const chatterPurpose='Ready to join Evzon as a chatter? Complete the form below. Our team will review your application and contact you about the next steps if you’re a good fit.';
export function JoinPurpose({kind}:{kind:'referral'|'chatter'}){
 const {t}=useI18n(),referral=kind==='referral',Icon=referral?Users:MessageSquare;
 return <section className="join-purpose" aria-label={t('Choose the right path')}>
  <div className="join-purpose-heading"><Icon size={19}/><strong>{t(referral?'Referral partner registration':'Chatter job application')}</strong></div>
  <p>{t(referral?referralPurpose:chatterPurpose)}</p>
  <PageLink href={referral?'/apply':'/register'}>{t(referral?'Looking for a chatter role? Apply here.':'Want to earn by referring people? Join our referral program.')}<ArrowRight size={15}/></PageLink>
 </section>;
}
