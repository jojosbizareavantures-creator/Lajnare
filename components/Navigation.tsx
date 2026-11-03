'use client';
import {createContext,useContext,useEffect,useRef,useState,type ComponentPropsWithoutRef,type ReactNode} from 'react';
import {createDocumentNavigation,isPlainInternalClick,type LeaveGuard} from '@/lib/document-navigation';
import {useI18n} from './I18n';

const NavigationContext=createContext<ReturnType<typeof createDocumentNavigation>|null>(null);
export function NavigationProvider({children}:{children:ReactNode}){
  const {t}=useI18n(),[state,setState]=useState({pending:false,error:''});
  const controller=useRef<ReturnType<typeof createDocumentNavigation>|null>(null);
  if(!controller.current)controller.current=createDocumentNavigation((href,replace)=>{
    if(replace)window.location.replace(href);else window.location.assign(href);
  },setState);
  return <NavigationContext.Provider value={controller.current}>{children}
    {state.pending&&<div className="navigation-status" role="status">{t('Opening page…')}</div>}
    {state.error&&<div className="navigation-status navigation-error" role="alert"><span>{t(state.error)}</span><button type="button" onClick={()=>setState({pending:false,error:''})}>{t('Dismiss')}</button></div>}
  </NavigationContext.Provider>;
}
export function useDocumentNavigation(){const context=useContext(NavigationContext);if(!context)throw new Error('NavigationProvider is required.');return context;}
export function useBeforeNavigation(guard:LeaveGuard){const context=useContext(NavigationContext);useEffect(()=>context?.register(guard),[context,guard]);}
export function WorkspaceLink({onClick,href,target,download,...props}:ComponentPropsWithoutRef<'a'>){
  const navigation=useContext(NavigationContext);
  return <a {...props} href={href} target={target} download={download} onClick={event=>{
    onClick?.(event);
    // Unmodified clicks wait for a pending workspace save. Other clicks retain
    // native browser behavior (new tab, keyboard modifiers and downloads).
    if(navigation?.hasGuard()&&isPlainInternalClick(event,href,target,download)){
      event.preventDefault();void navigation.navigate(href!);
    }
  }}/>;
}
