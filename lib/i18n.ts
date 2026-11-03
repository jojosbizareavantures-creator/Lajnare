import {mk} from './locales/mk';

export type Language='en'|'mk';
export const LANGUAGE_COOKIE='evzon_language';
export const LANGUAGE_STORAGE='evzon.language';
export function languageFrom(value:unknown):Language|undefined{return value==='en'||value==='mk'?value:undefined;}
export function savedLanguage():Language|undefined{try{return languageFrom(localStorage.getItem(LANGUAGE_STORAGE));}catch{return undefined;}}
export function saveLanguage(value:Language){
 const language=languageFrom(value);if(!language)return;
 try{localStorage.setItem(LANGUAGE_STORAGE,language);}catch{/* Cookies still preserve the choice when storage is unavailable. */}
 try{if(typeof document!=='undefined')document.cookie=`${LANGUAGE_COOKIE}=${language}; Path=/; Max-Age=31536000; SameSite=Lax${typeof location!=='undefined'&&location.protocol==='https:'?'; Secure':''}`;}catch{/* Keep the current-session selection if cookies are blocked too. */}
}
const normalize=(s:string)=>s.replace(/\s+/g,' ').trim();
const entries=Object.entries(mk).map(([en,text])=>[normalize(en),text] as const);
const dictionary=new Map(entries);
const escape=(s:string)=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
// Named placeholders let calculated figures stay untouched inside translated messages.
// Prefer the most specific sentence: a broad "{count} days" pattern must not
// capture "After 7 completed training days" and leave part of it untranslated.
const templates=entries.filter(([en])=>/\{\w+\}/.test(en)).sort(([a],[b])=>b.replace(/\{\w+\}/g,'').length-a.replace(/\{\w+\}/g,'').length).map(([en,text])=>{
 const keys=[...en.matchAll(/\{(\w+)\}/g)].map(m=>m[1]);
 const pattern=new RegExp('^'+en.split(/\{\w+\}/g).map(escape).join('(.+?)')+'$');
 return {pattern,keys,text};
});
const phrases=entries.filter(([en])=>en.length>=12&&!/\{\w+\}/.test(en)).sort((a,b)=>b[0].length-a[0].length);
const phrasePattern=phrases.length?new RegExp(phrases.map(([en])=>escape(en)).join('|'),'g'):null;
export function translateText<T>(value:T,language:Language):T{
 if(language==='en'||typeof value!=='string'||!/[A-Za-z]/.test(value))return value;
 const clean=normalize(value),translated=dictionary.get(clean);
 const whitespace=(text:string)=>(value.match(/^\s*/)?.[0]||'')+text+(value.match(/\s*$/)?.[0]||'');
 if(translated!==undefined)return whitespace(translated) as T;
 for(const template of templates){const match=clean.match(template.pattern);if(match){const params=Object.fromEntries(template.keys.map((key,i)=>[key,match[i+1]]));return whitespace(template.text.replace(/\{(\w+)\}/g,(_,key)=>params[key])) as T;}}
 if(clean.endsWith(' slider'))return whitespace(String(translateText(clean.slice(0,-7),language))+' · лизгач') as T;
 // Combined interface copy can contain several independently translated sentences.
 if(phrasePattern){const text=value.replace(phrasePattern,match=>dictionary.get(normalize(match))||match);if(text!==value)return text as T;}
 for(const [prefix,key] of [['Edit ','Edit'],['Delete ','Delete'],['Search ','Search'],['Check ','Check'],['Add shift ','Add shift']] as const){if(clean.startsWith(prefix))return whitespace((dictionary.get(key)||key)+' '+String(translateText(clean.slice(prefix.length),language))) as T;}
 return value;
}
