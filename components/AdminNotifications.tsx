'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {WorkspaceLink as Link} from './Navigation';
import {Bell,CheckCheck,ArrowUpRight,UserRoundPlus,X} from 'lucide-react';
import {useI18n} from './I18n';
import {api} from '@/lib/referrals';
type Notice={id:string;application_id:string|null;referral_id:string|null;kind:'Application'|'Referral';candidate_name:string;created_at:string;read_at:string|null};
type Inbox={notifications:Notice[];unread:number};
const destination=(n:Notice)=>n.application_id?'/adminpanel/applications?application='+encodeURIComponent(n.application_id):'/adminpanel/referrals';
export function AdminNotifications({financialAlerts=0}:{financialAlerts?:number}){
 const {t:tr,language}=useI18n(),[data,set]=useState<Inbox>({notifications:[],unread:0}),[open,so]=useState(false),[error,se]=useState(''),[busy,sb]=useState(false),[loading,sl]=useState(true),[latest,sLatest]=useState<Notice|null>(null);
 const root=useRef<HTMLDivElement>(null),seen=useRef<Set<string>|null>(null),inFlight=useRef(false),alive=useRef(true);
 const refresh=useCallback(async()=>{
  if(inFlight.current)return;inFlight.current=true;
  try{const next=await api<Inbox>('/api/notifications');if(!alive.current)return;
   const fresh=next.notifications.find(n=>!n.read_at&&seen.current&&!seen.current.has(n.id));
   if(fresh)sLatest(fresh);seen.current=new Set(next.notifications.map(n=>n.id));set(next);se('');
  }catch{if(alive.current)se('Application alerts could not refresh. Retry to check for new applications.');}
  finally{inFlight.current=false;if(alive.current)sl(false);}
 },[]);
 useEffect(()=>{alive.current=true;void refresh();const onFocus=()=>{if(document.visibilityState==='visible')void refresh();};const timer=setInterval(onFocus,30000);window.addEventListener('focus',onFocus);document.addEventListener('visibilitychange',onFocus);return()=>{alive.current=false;clearInterval(timer);window.removeEventListener('focus',onFocus);document.removeEventListener('visibilitychange',onFocus);};},[refresh]);
 useEffect(()=>{if(!open)return;const close=(e:PointerEvent)=>{if(!root.current?.contains(e.target as Node))so(false);};const escape=(e:KeyboardEvent)=>{if(e.key==='Escape'){so(false);root.current?.querySelector<HTMLButtonElement>('.notification-trigger')?.focus();}};document.addEventListener('pointerdown',close);document.addEventListener('keydown',escape);return()=>{document.removeEventListener('pointerdown',close);document.removeEventListener('keydown',escape);};},[open]);
 const mark=async(ids:string[])=>{if(!ids.length||busy)return;sb(true);try{await api('/api/notifications',{ids},'PATCH',{keepalive:true});await refresh();}catch{se('Notifications could not be marked as read. Please retry.');}finally{sb(false);}};
 return <div className="admin-notifications" ref={root}>
  <button type="button" className="bell notification-trigger" aria-label={tr('Application notifications')+(data.unread?' · '+data.unread:'')} aria-expanded={open} aria-controls="admin-notifications" onClick={()=>{so(!open);if(!open)void refresh();}}><Bell size={18}/>{data.unread>0?<span className="notification-count">{data.unread>99?'99+':data.unread}</span>:error?<span className="notification-count notification-error">!</span>:financialAlerts>0?<i/>:null}</button>
  {latest&&!open&&<div className="notification-toast" role="status"><UserRoundPlus size={19}/><Link href={destination(latest)} onClick={()=>sLatest(null)}><b>{tr('New application received')}</b><span>{latest.candidate_name}</span></Link><button aria-label={tr('Dismiss notification')} onClick={()=>sLatest(null)}><X size={15}/></button></div>}
  {open&&<section className="notification-panel" id="admin-notifications" aria-label={tr('Application notifications')}>
   <header><div><b>{tr('Applications inbox')}</b><small>{data.unread} {tr('unread notifications')}</small></div><button disabled={busy||!data.notifications.some(n=>!n.read_at)} onClick={()=>void mark(data.notifications.filter(n=>!n.read_at).map(n=>n.id))} title={tr('Mark shown as read')} aria-label={tr('Mark shown as read')}><CheckCheck size={19}/></button></header>
   {error&&<div className="notification-feedback" role="alert">{tr(error)} <button onClick={()=>void refresh()}>{tr('Retry')}</button></div>}
   <div className="notification-list">{loading?<p>{tr('Loading notifications…')}</p>:!data.notifications.length?<div className="notification-empty"><Bell size={24}/><b>{tr('You’re all caught up')}</b><p>{tr('New applications will appear here automatically.')}</p></div>:data.notifications.map(n=><article key={n.id} className={n.read_at?'':'unread'}><UserRoundPlus size={16}/><div><Link href={destination(n)} onClick={()=>{so(false);sLatest(null);void mark([n.id]);}}><b>{n.candidate_name}</b><span>{tr(n.kind==='Application'?'New candidate application':'New referred candidate')}</span></Link><time dateTime={n.created_at}>{new Date(n.created_at).toLocaleString(language==='mk'?'mk-MK':'en-GB',{dateStyle:'medium',timeStyle:'short'})}</time></div>{!n.read_at&&<button disabled={busy} aria-label={tr('Mark as read')+': '+n.candidate_name} title={tr('Mark as read')} onClick={()=>void mark([n.id])}><CheckCheck size={15}/></button>}</article>)}</div>
   <footer><Link href="/adminpanel/applications" onClick={()=>so(false)}>{tr('View all applications')}<ArrowUpRight size={14}/></Link><Link href="/adminpanel/insights" onClick={()=>so(false)}>{tr('Management alerts')}{financialAlerts>0&&' · '+financialAlerts}</Link><small>{tr('Checks for new applications every 30 seconds while this workspace is open.')}</small></footer>
  </section>}
 </div>;
}
