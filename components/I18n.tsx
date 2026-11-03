'use client';
import {createContext,useContext,useEffect,useMemo,useState} from 'react';
import {Languages} from 'lucide-react';
import {languageFrom,translateText,savedLanguage,saveLanguage,type Language} from '@/lib/i18n';
type LocaleContext={language:Language;setLanguage:(language:Language)=>void;t:<T>(value:T)=>T};
const Locale=createContext<LocaleContext>({language:'en',setLanguage:()=>{},t:value=>value});
export function I18nProvider({children,initialLanguage}:{children:React.ReactNode;initialLanguage?:Language}){
 const [language,set]=useState<Language>(initialLanguage||'en');
 useEffect(()=>{const next=languageFrom(initialLanguage)||savedLanguage()||'en';set(next);saveLanguage(next);},[initialLanguage]);
 useEffect(()=>{document.documentElement.lang=language;},[language]);
 const value=useMemo<LocaleContext>(()=>({language,setLanguage:next=>{const valid=languageFrom(next);if(valid){set(valid);saveLanguage(valid);}},t:v=>translateText(v,language)}),[language]);
 return <Locale.Provider value={value}>{children}</Locale.Provider>;
}
export const useI18n=()=>useContext(Locale);
export function LanguageSelect({className=''}:{className?:string}){const {language,setLanguage,t}=useI18n();return <label className={'language-select '+className}><Languages size={16} aria-hidden="true"/><select aria-label={t('Language')} value={language} onChange={e=>{const next=languageFrom(e.target.value);if(next)setLanguage(next);}}><option value="en" lang="en">English</option><option value="mk" lang="mk">Македонски</option></select></label>}
