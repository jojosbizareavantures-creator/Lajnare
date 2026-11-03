'use client';
import {useI18n,LanguageSelect} from '@/components/I18n';
import {createContext,useContext,useEffect,useState,useCallback} from 'react';
import {PageLink as Link} from './marketing/PublicUI';
import {usePathname} from 'next/navigation';
import {useDocumentNavigation} from './Navigation';
import {LockKeyhole,ArrowRight,ArrowLeft,LogOut,ShieldCheck,Users} from 'lucide-react';
import type {Profile} from '@/lib/cloud-contract';
import {api} from '@/lib/referrals';
import {canEnter,loginDestination,profileHome} from '@/lib/navigation';
import {Button,Card} from './ui';
import {JoinPurpose} from './JoinPurpose';
type Session={profile:Profile|null;ready:boolean;error:string;refresh:()=>Promise<Profile|null>;logout:()=>Promise<void>};
const AuthContext=createContext<Session|null>(null);
export const useAuth=()=>useContext(AuthContext);
export function SessionProvider({children}:{children:React.ReactNode}){const {t:tr}=useI18n();
 const [profile,set]=useState<Profile|null>(null),[ready,load]=useState(false),[error,se]=useState('');const {navigate,prepare}=useDocumentNavigation();
 const refresh=useCallback(async()=>{try{const data=await api('/api/auth');set(data.profile);se('');return data.profile as Profile|null;}catch(e){se((e as Error).message);throw e;}finally{load(true);}},[]);
 useEffect(()=>{void refresh().catch(()=>{});},[refresh]);
 const logout=async()=>{await prepare();await api('/api/auth',{action:'signout'});void navigate(profile?.role==='CHATTER'?'/chatterportal':'/login',true);};
 return <AuthContext.Provider value={{profile,ready,error,refresh,logout}}>{children}</AuthContext.Provider>;
}
function Loading(){const {t:tr}=useI18n();return <div className="loading"><b>EVZON</b><p>{tr("Securing your workspace…")}</p></div>}
export function AuthGate({children,role}:{children:React.ReactNode;role:Profile['role']}){const {t:tr}=useI18n();
 const auth=useAuth()!,{navigate}=useDocumentNavigation(),pathname=usePathname()||'/login',{profile,ready,error}=auth;
 useEffect(()=>{if(!ready||error)return;if(!profile)void navigate('/login?next='+encodeURIComponent(pathname),true);else if(profile.status!=='Suspended'&&profile.role!==role)void navigate(profileHome(profile),true);},[ready,profile,error,role,navigate,pathname]);
 if(error)return <div className="auth-shell"><LanguageSelect className="auth-language"/><Card title={tr("Unable to connect")}><p role="alert">{tr(error)}</p><Button onClick={()=>auth.refresh().catch(()=>{})}>{tr("Retry connection")}</Button><Link className="btn" href="/landing">{tr("Back to website")}</Link></Card></div>;
 if(!ready||!profile)return <Loading/>;
 if(profile.status==='Suspended'||profile.role==='ADMIN'&&profile.status!=='Approved')return <div className="auth-shell"><LanguageSelect className="auth-language"/><Card title={tr(profile.status==='Suspended'?'Account suspended':'Access awaiting approval')}><p>{tr("Contact an administrator to review your access.")}</p><SignOut/><Link className="btn" href="/landing">{tr("Back to website")}</Link></Card></div>;
 if(!canEnter(profile,role))return <Loading/>;
 return <>{children}</>;
}
export function AccountEntry({mode='signin'}:{mode?:'signin'|'signup'|'reset'}){const {t:tr}=useI18n();
 const auth=useAuth()!,{navigate}=useDocumentNavigation();
 const destination=(p:Profile)=>loginDestination(p,new URLSearchParams(location.search).get('next'));
 useEffect(()=>{if(mode==='signin'&&auth.ready&&auth.profile)void navigate(destination(auth.profile),true);},[auth.ready,auth.profile,mode,navigate]);
 return <AuthForm key={mode} mode={mode} initialError={auth.error} refresh={async()=>{const p=await auth.refresh();if(p)await navigate(destination(p),true);}}/>;
}
export function RecoveryPage(){const {t:tr}=useI18n();const auth=useAuth()!,{navigate}=useDocumentNavigation();if(!auth.ready)return <Loading/>;return <div className="auth-shell"><LanguageSelect className="auth-language"/><div className="application-card"><Link className="back-link" href="/landing"><ArrowLeft size={16}/>{tr(" Back to Evzon")}</Link><Card title={tr("Set a new password")}>{auth.profile?<PasswordForm done={()=>{void navigate(profileHome(auth.profile!),true);}}/>:<><p>{tr(auth.error||'Open the latest password-reset email to continue. Your link may have expired or already been used.')}</p><Link className="btn primary" href="/forgot-password">{tr("Request a new reset email")}</Link></>}</Card></div></div>}
export function AuthForm({refresh,initialError='',mode='signin'}:{refresh:()=>Promise<void>;initialError?:string;mode?:'signin'|'signup'|'reset'}){const {t:tr}=useI18n();
 const [name,sn]=useState(''),[email,se]=useState(''),[password,sp]=useState(''),[busy,sb]=useState(false),[err,error]=useState(initialError),[notice,sNotice]=useState('');
 useEffect(()=>{if(new URLSearchParams(location.search).has('auth_error'))error('This confirmation link has expired or was already used. Request a new email or sign in again.');},[]);
 return <div className="auth-page"><LanguageSelect className="auth-language"/><div className="auth-story"><Link href="/landing" className="brand"><span className="brand-mark"><i/><i/><i/></span><span>EVZON<small>{tr("OPERATIONS & PARTNERS")}</small></span></Link><div><span className="eyebrow">{tr("PEOPLE. PERFORMANCE. POTENTIAL.")}</span><h1>{tr("One workspace.")}<br/><em>{tr("Every opportunity.")}</em></h1><p>{tr("Build a stronger workforce. Connect the right people, track their progress and share in their success.")}</p><div className="auth-features"><span><ShieldCheck size={18}/>{tr(" Protected company workspace")}</span><span><Users size={18}/>{tr(" Your own referral & earnings portal")}</span></div></div><Link href="/landing" className="back-link"><ArrowLeft size={16}/>{tr(" Explore Evzon")}</Link></div><div className="auth-form-wrap"><div className="auth-form"><div className="auth-icon"><LockKeyhole size={23}/></div><h2>{tr(mode==='signup'?'Create a referral partner account':mode==='reset'?'Reset your password':'Welcome to Evzon')}</h2><p>{tr(mode==='signup'?'Get your personal referral code and link. Verify your email to start sharing; account approval is required before rewards can be approved and paid.':mode==='reset'?'We’ll send instructions to your registered email.':'Sign in to continue to your workspace.')}</p>{mode==='signup'&&<JoinPurpose kind="referral"/>}<form onSubmit={async e=>{e.preventDefault();if(busy)return;sb(true);error('');sNotice('');try{const result=await api('/api/auth',{action:mode,email:email.trim(),password,name});if(mode==='signin')await refresh();else sNotice(result.message);sp('');}catch(e){error((e as Error).message);}finally{sb(false);}}}>{mode==='signup'&&<label className="field"><span>{tr("Full name")}</span><input required maxLength={100} autoComplete="name" value={name} onChange={e=>sn(e.target.value)}/></label>}<label className="field"><span>{tr("Email address")}</span><input type="email" required autoComplete="email" value={email} onChange={e=>se(e.target.value)}/></label>{mode!=='reset'&&<label className="field"><span>{tr("Password")}</span><input type="password" required minLength={mode==='signup'?12:1} maxLength={256} autoComplete={mode==='signup'?'new-password':'current-password'} value={password} onChange={e=>sp(e.target.value)}/>{mode==='signup'&&<small>{tr("At least 12 characters.")}</small>}</label>}{err&&<p role="alert" className="negative">{tr(err)}</p>}{notice&&<p role="status" className="success">{tr(notice)}</p>}<Button primary type="submit" disabled={busy}>{tr(busy?'Please wait…':mode==='signup'?'Create referrer account':mode==='reset'?'Send reset email':'Sign in')}<ArrowRight size={16}/></Button></form>{mode!=='reset'&&<button type="button" className="auth-resend" disabled={busy} onClick={async()=>{if(!/^\S+@\S+\.\S+$/.test(email.trim())){error("Enter a valid email.");return;}sb(true);error('');sNotice('');try{const result=await api('/api/auth',{action:'resend',email:email.trim()});sNotice(result.message);}catch(e){error((e as Error).message);}finally{sb(false);}}}>{tr("Resend verification email")}</button>}<div className="auth-links">{mode==='signin'?<><Link href="/register">{tr("Create a referrer account")}</Link><Link href="/forgot-password">{tr("Forgot password?")}</Link></>:<Link href="/login">{tr("Back to sign in")}</Link>}</div>{mode==='signin'&&<p className="auth-note">{tr("Want to work as a chatter? ")}<Link href="/apply">{tr("Apply for a chatter role")}</Link>{tr(". No account is required to apply.")}</p>}<Link href="/landing" className="back-link auth-back"><ArrowLeft size={14}/>{tr(" Back to website")}</Link></div></div></div>
}
export function PasswordForm({done}:{done?:()=>void}){const {t:tr}=useI18n();const [password,sp]=useState(''),[again,sa]=useState(''),[message,sm]=useState(''),[busy,sb]=useState(false);return <form className="stack" onSubmit={async e=>{e.preventDefault();if(password!==again){sm('Passwords do not match.');return;}sb(true);try{await api('/api/auth',{action:'password',password});sp('');sa('');sm('Password updated.');done?.();}catch(e){sm((e as Error).message);}finally{sb(false);}}}><label className="field"><span>{tr("New password")}</span><input required type="password" minLength={12} maxLength={256} autoComplete="new-password" value={password} onChange={e=>sp(e.target.value)}/></label><label className="field"><span>{tr("Confirm new password")}</span><input required type="password" minLength={12} autoComplete="new-password" value={again} onChange={e=>sa(e.target.value)}/></label>{message&&<p role="status">{tr(message)}</p>}<Button primary disabled={busy} type="submit">{tr(busy?'Updating…':'Update password')}</Button></form>}
export function SignOut(){
 const {t:tr}=useI18n(),auth=useAuth(),[err,se]=useState(''),[busy,sb]=useState(false);
 const signOut=async()=>{
  if(busy)return;sb(true);se('');
  try{await auth?.logout();}catch(e){se((e as Error).message);}finally{sb(false);}
 };
 return <><Button disabled={busy} onClick={signOut}><LogOut size={15}/>{tr(busy?'Please wait…':' Sign out')}</Button>{err&&<span role="alert" className="negative">{tr(err)}</span>}</>;
}
