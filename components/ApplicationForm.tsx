'use client';
import {useEffect,useState} from 'react';
import {ArrowRight,CheckCircle2,Monitor,ShieldCheck} from 'lucide-react';
import {useI18n} from './I18n';
import {ageOn,blankApplication,equipmentOptions,validateApplication,type ApplicationInput} from '@/lib/applications';
import {rememberReferral,rememberedReferral} from '@/lib/referral-attribution';
import {PageLink} from './marketing/PublicUI';
import {api} from '@/lib/referrals';
export const applicationPrivacy='We use your application details to review your suitability and contact you about recruitment. We also record the submission time, IP address when available, and basic browser and device information to help prevent spam and review submissions. Only approved administrators can view these details. If you use a referral code, the referring partner can follow your application stage; they cannot see your birth date, IP address or device information.';
export function ApplicationForm({referralCode=''}:{referralCode?:string}){
 const {t:tr,language}=useI18n(),[data,set]=useState<ApplicationInput>({...blankApplication,code:referralCode}),[busy,sb]=useState(false),[error,se]=useState(''),[done,sd]=useState(false);
 useEffect(()=>{const code=referralCode.trim().toUpperCase()||rememberedReferral();if(referralCode)rememberReferral(code);set(d=>({...d,code}));},[referralCode]);
 const age=ageOn(data.date_of_birth),change=(key:keyof ApplicationInput,value:string|boolean)=>{set(d=>({...d,[key]:value}));if(key==='code')rememberReferral(String(value));};
 if(done)return <div className="application-success" role="status"><CheckCircle2 size={38}/><h2>{tr('Application received')}</h2><p>{tr('Thank you for applying. The recruitment team will review your details and contact you using the information you provided if your application progresses.')}</p><p>{tr('Submitting an application does not guarantee an interview, a job or income.')}</p><PageLink className="marketing-button primary" href="/landing">{tr('Back to Evzon')}<ArrowRight size={16}/></PageLink></div>;
 const input=(key:keyof ApplicationInput,label:string,type='text',max=100,autoComplete?:string)=><label className="field" key={key}><span>{tr(label)} *</span><input name={key} type={type} required maxLength={max} autoComplete={autoComplete} value={String(data[key])} onChange={e=>change(key,e.target.value)} onInput={key==='date_of_birth'?e=>change(key,e.currentTarget.value):undefined} {...(key==='date_of_birth'?{min:'1900-01-01','aria-describedby':'applicant-age'}:{})}/></label>;
 return <form className="candidate-application" onSubmit={async e=>{e.preventDefault();if(busy)return;se('');let checked;try{checked=validateApplication({...data,language});}catch(e){se((e as Error).message);return;}sb(true);try{
  const result=await api<{submitted?:boolean;error?:string}>('/api/apply',checked);
  if(result.submitted!==true)throw new Error(result.error||'Your application could not be submitted. Please try again.');sd(true);rememberReferral('');set({...blankApplication});
 }catch(e){se(e instanceof TypeError?'Connection failed. Your details are still here; please try again.':(e as Error).message);}finally{sb(false);}}}>
 <div className="application-requirements"><span><Monitor size={17}/>{tr('PC or laptop required')}</span><span><ShieldCheck size={17}/>{tr('Applicants must be 18+')}</span></div>
 <p className="form-help">{tr('Fields marked * are required. Referral codes are optional.')}</p>{data.code&&<div className="referral-credit" role="status"><span>{tr("Referral code included:")} <b>{data.code}</b><small className="cell-note">{tr("Your application will use this code. You can change or remove it below.")}</small></span></div>}
 <fieldset disabled={busy}><legend>{tr('About you')}</legend><div className="form-grid">
 {input('first_name','First name','text',60,'given-name')}{input('last_name','Last name','text',60,'family-name')}
 {input('country','Country','text',80,'country-name')}{input('city','City','text',100,'address-level2')}
 {input('date_of_birth','Date of birth','date',10,'bday')}
 <label className="field"><span>{tr('Age')}</span><output id="applicant-age" className={age!==null&&age<18?'negative':''}>{age===null?tr('Calculated from your date of birth'):age+' '+tr('years old')}</output></label>
 <label className="field"><span>{tr('Gender')} *</span><select name="gender" required value={data.gender} onChange={e=>change('gender',e.target.value)}><option value="">{tr('Select an option')}</option><option value="M">{tr('Male (M)')}</option><option value="F">{tr('Female (F)')}</option></select></label>
 <label className="field"><span>{tr('Your computer')} *</span><select name="equipment" required value={data.equipment} onChange={e=>change('equipment',e.target.value)}><option value="">{tr('Select an option')}</option>{equipmentOptions.map(x=><option key={x} value={x}>{tr(x)}</option>)}</select><small>{tr('You need access to a desktop PC or laptop and a reliable internet connection. A phone alone is not sufficient.')}</small></label>
 </div></fieldset>
 <fieldset disabled={busy}><legend>{tr('How we can reach you')}</legend><div className="form-grid">{input('phone','Phone number','tel',40,'tel')}{input('email','Contact email','email',254,'email')}</div><p className="form-help">{tr('Include your country calling code. Check your contact details before submitting.')}</p></fieldset>
 <fieldset disabled={busy}><legend>{tr('A little more about you')}</legend><div className="form-grid">
 <label className="field full"><span>{tr('Experience (optional)')}</span><textarea maxLength={1000} value={data.experience} onChange={e=>change('experience',e.target.value)} placeholder={tr('Tell us about your English writing, customer support or chatting experience.')}/></label>
 <label className="field full"><span>{tr('Availability (optional)')}</span><input maxLength={300} value={data.availability} onChange={e=>change('availability',e.target.value)} placeholder={tr('When could you start, and which hours are you available?')}/></label>
 <label className="field full"><span>{tr('Message / additional information (optional)')}</span><textarea maxLength={2000} value={data.message} onChange={e=>change('message',e.target.value)} placeholder={tr('Anything else you would like the recruitment team to know.')}/><small>{data.message.length} / 2000</small></label>
 <label className="field"><span>{tr('Referral code (optional)')}</span><input maxLength={12} autoComplete="off" value={data.code} onChange={e=>change('code',e.target.value.toUpperCase())}/><small>{tr('Leave this empty if you are applying directly.')}</small><small>{tr('We remember a referral link on this device for up to 30 days so you can return after reading the job guide. You can change or remove the code at any time.')}</small></label>
 <label className="honeypot" aria-hidden="true">{tr('Website')}<input tabIndex={-1} autoComplete="off" value={data.website} onChange={e=>change('website',e.target.value)}/></label>
 </div></fieldset>
 <section className="application-privacy-box" id="application-privacy"><h3>{tr('Application privacy')}</h3><p>{tr(applicationPrivacy)}</p><p>{tr('Please do not include account passwords, identity documents or other unnecessary sensitive information. To request a correction or removal, reply to the recruitment team when they contact you.')}</p></section>
 <label className="check-line"><input type="checkbox" required disabled={busy} checked={data.adult} onChange={e=>change('adult',e.target.checked)}/>{tr('I am at least 18 and understand that the role involves written conversations on behalf of adult creators on OnlyFans and Fanvue.')}</label>
 <label className="check-line"><input type="checkbox" required disabled={busy} checked={data.consent} onChange={e=>change('consent',e.target.checked)}/>{tr('I have read the application privacy notice and agree to share these details with Evzon for recruitment.')}</label>
 {error&&<p className="application-error" role="alert">{tr(error)}</p>}
 <button className="marketing-button primary" type="submit" disabled={busy}>{tr(busy?'Submitting…':'Submit chatter application')}<ArrowRight size={17}/></button>
 </form>;
}
