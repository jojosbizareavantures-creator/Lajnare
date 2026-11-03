'use client';
import {useI18n} from '@/components/I18n';
import React,{createContext,useContext,useState,useEffect,useRef,useCallback} from 'react';
import {State,Row,initial,calculate,uid,validBackup} from '@/lib/finance';
import {api,rewardRows,type Portal} from '@/lib/referrals';
import {download,Button} from './ui';
import {useAuth} from './Auth';
import {useBeforeNavigation} from './Navigation';
import {saveBeforeLeaving} from '@/lib/document-navigation';
export type Store={s:State;f:ReturnType<typeof calculate>;update:(key:keyof State,value:any,action?:string)=>void;save:(key:keyof State,row:Row)=>void;remove:(key:keyof State,id:string)=>void;replace:(s:State)=>void;toast:(msg:string)=>void;notice:string;sync?:string;portal?:Portal;referralAction?:(action:string,data?:unknown)=>Promise<void>;reload?:()=>Promise<void>;flush?:()=>Promise<void>};
export const Context=createContext<Store>(null!);
export const useStore=()=>useContext(Context);
const strip=(s:State)=>({...s,referralRewards:undefined});
export function Provider({children}:{children:React.ReactNode}){const {t:tr}=useI18n();const auth=useAuth();const [s,set]=useState<State>(initial),[ready,load]=useState(false),[notice,notify]=useState(''),[error,se]=useState(''),[sync,ss]=useState('Connecting…'),[portal,sp]=useState<Portal>(),[migration,sm]=useState(false),[dirty,sd]=useState(0);const latest=useRef(s),revision=useRef(0),saved=useRef(''),inflight=useRef(false),savePromise=useRef<Promise<void>|null>(null),dirtyRef=useRef(0);latest.current=s;dirtyRef.current=dirty;const draftKey='evzon.draft.'+(auth?.profile?.id||'admin');
 const apply=useCallback((v:any)=>{revision.current=v.workspace.revision;const next=v.workspace.state?{...initial,...v.workspace.state,referralRewards:rewardRows(v.portal.rewards)}:null;sp(v.portal);if(next){if(!validBackup(next))throw Error('The saved workspace could not be validated. Please export a database backup before continuing.');set(next);latest.current=next;saved.current=JSON.stringify(strip(next));ss('Saved to cloud');}else{sm(true);ss('Setup required');}load(true);},[]);
 const reload=useCallback(async()=>{try{const v=await api('/api/workspace');apply(v);se('');sd(0);try{localStorage.removeItem(draftKey);}catch{}}catch(e){se((e as Error).message);load(true);}},[apply,draftKey]);
 useEffect(()=>{let live=true;api('/api/workspace').then(v=>{if(!live)return;apply(v);try{if(localStorage.getItem(draftKey))se('An unsaved draft is available from this device. Export it before loading the latest cloud data.');}catch{}}).catch(e=>{if(live){se(e.message);load(true);}});return()=>{live=false;};},[apply,draftKey]);
 const persist=useCallback(():Promise<void>=>{
  if(savePromise.current)return savePromise.current;
  const snapshot=latest.current,body=JSON.stringify(strip(snapshot));
  if(body===saved.current)return Promise.resolve();
  if(!ready||migration||error)return Promise.reject(new Error(error||'The workspace is not ready to save. Please try again.'));
  inflight.current=true;ss('Saving…');
  savePromise.current=Promise.resolve().then(async()=>{
   try{
    if(!validBackup(snapshot))throw Error('Some values are incomplete or invalid. Complete them, then retry saving.');
    try{localStorage.setItem(draftKey,JSON.stringify(snapshot));}catch{}
    const v=await api('/api/workspace',{state:strip(snapshot),revision:revision.current},'PUT');
    revision.current=v.workspace.revision;saved.current=body;sp(v.portal);
    set(current=>({...current,referralRewards:rewardRows(v.portal.rewards)}));ss('Saved to cloud');
    if(JSON.stringify(strip(latest.current))===body){try{localStorage.removeItem(draftKey);}catch{}}
   }catch(e){se((e as Error).message);ss('Not saved');throw e;}
   finally{inflight.current=false;savePromise.current=null;sd(x=>x+1);}
  });
  return savePromise.current;
 },[ready,migration,error,draftKey]);
 const beforeNavigation=useCallback(()=>{
  if(!saved.current)return;
  return saveBeforeLeaving(()=>JSON.stringify(strip(latest.current))!==saved.current,persist);
 },[persist]);
 useBeforeNavigation(beforeNavigation);
 useEffect(()=>{if(!ready||error||migration)return;const timer=setTimeout(()=>{void persist().catch(()=>{});},700);return()=>clearTimeout(timer);},[s,dirty,ready,error,migration,persist]);
 useEffect(()=>{if(!notice)return;const timer=setTimeout(()=>notify(''),4000);return()=>clearTimeout(timer);},[notice]);
 useEffect(()=>{const leaving=(e:BeforeUnloadEvent)=>{if(saved.current&&JSON.stringify(strip(latest.current))!==saved.current){e.preventDefault();e.returnValue='';}};window.addEventListener('beforeunload',leaving);return()=>window.removeEventListener('beforeunload',leaving);},[]);
 const update=(key:keyof State,value:any,action='Updated '+key)=>{if(key==='referralRewards')return;set(prev=>{let before:any=prev[key],after:any=value;if(Array.isArray(before)&&Array.isArray(after)){const old=before as Row[],next=after as Row[];const changed=new Set([...old.map(r=>r.id),...next.map(r=>r.id)].filter(id=>JSON.stringify(old.find(r=>r.id===id))!==JSON.stringify(next.find(r=>r.id===id))));before=old.filter(r=>changed.has(r.id));after=next.filter(r=>changed.has(r.id));}const next={...prev,[key]:value,history:[{id:uid(),date:new Date().toISOString(),action,before:JSON.stringify(before),after:JSON.stringify(after)},...prev.history].slice(0,200)};latest.current=next;try{localStorage.setItem(draftKey,JSON.stringify(next));}catch{}return next;});ss('Unsaved changes');};
 const save=(key:keyof State,row:Row)=>{const rows=latest.current[key] as Row[];update(key,rows.some(r=>r.id===row.id)?rows.map(r=>r.id===row.id?row:r):[...rows,row],`Saved ${row.name||row.id} in ${key}`);};
 const remove=(key:keyof State,id:string)=>{if(confirm(tr('Delete this record? This cannot be undone.')))update(key,(latest.current[key] as Row[]).filter(r=>r.id!==id),'Deleted '+id+' from '+key);};
 const referralAction=async(action:string,data:unknown={})=>{if(error||inflight.current||JSON.stringify(strip(latest.current))!==saved.current)throw Error('Wait for the workspace to finish saving before updating referrals.');const p=await api<Portal>('/api/referrals',{action,data});sp(p);set(v=>({...v,referralRewards:rewardRows(p.rewards)}));notify('Referral records updated');};
 const exportDraft=()=>{let raw:string|null=null;try{raw=localStorage.getItem(draftKey);}catch{}download('evzon-unsaved-draft.json',raw||JSON.stringify(s,null,2),'application/json');};
 const initialize=async(importLocal:boolean)=>{try{let next=structuredClone(initial);if(importLocal){const raw=localStorage.getItem('evzon.operations.v1');if(!raw)throw Error('No previous browser data was found. Use a JSON backup in Settings after opening the workspace.');const parsed=JSON.parse(raw);if(!validBackup(parsed))throw Error('The previous browser data is invalid. It has been preserved.');next=parsed;}const v=await api('/api/workspace',{state:strip(next),revision:revision.current},'PUT');apply(v);sm(false);se('');}catch(e){se((e as Error).message);}};
 if(!ready)return <div className="loading"><b>EVZON</b><p>{tr("Loading your company workspace…")}</p></div>;
 if(migration)return <div className="auth-shell"><section className="card application-card"><h2>{tr("Your cloud workspace is ready")}</h2><p>{tr("Import the records saved in this browser, or start with your original editable planning assumptions. Your old browser copy is preserved.")}</p><div className="actions"><Button primary onClick={()=>initialize(true)}>{tr("Import this browser’s workspace")}</Button><Button onClick={()=>initialize(false)}>{tr("Start with defaults")}</Button></div>{error&&<p className="negative">{tr(error)}</p>}</section></div>;
 if(!portal)return <div className="auth-shell"><section className="card"><h2>{tr("Workspace unavailable")}</h2><p className="negative">{tr(error)}</p><Button onClick={reload}>{tr("Retry connection")}</Button></section></div>;
 return <Context.Provider value={{s,f:calculate(s),update,save,remove,replace:v=>{const next={...v,referralRewards:s.referralRewards};latest.current=next;set(next);try{localStorage.setItem(draftKey,JSON.stringify(next));}catch{}ss('Unsaved changes');},toast:notify,notice,sync,portal,referralAction,reload,flush:async()=>{await beforeNavigation();}}}>{error&&<div className="storage-error"><span>{tr(error)}</span><Button onClick={exportDraft}>{tr("Export draft")}</Button><Button onClick={()=>{se('');sd(x=>x+1);}}>{tr("Retry save")}</Button><Button onClick={()=>{if(confirm(tr('Discard this device’s unsaved changes and load the cloud version? Export a draft first if needed.')))reload();}}>{tr("Load latest")}</Button></div>}{children}{notice&&<div className="toast">{tr(notice)}</div>}</Context.Provider>;
}
