'use client';
import {Fragment,useEffect,useRef,useSyncExternalStore,type ReactNode} from 'react';
// Media queries are read as external stores, so server markup and the first client render agree.
const media=(query:string)=>({subscribe:(notify:()=>void)=>{const list=matchMedia(query);list.addEventListener('change',notify);return()=>list.removeEventListener('change',notify);},matches:()=>matchMedia(query).matches});
const finePointer=media('(hover: hover) and (pointer: fine)'),reducedMotion=media('(prefers-reduced-motion: reduce)');
const useCalm=()=>useSyncExternalStore(reducedMotion.subscribe,reducedMotion.matches,()=>true);
// Headline letters gain weight and sharpness near the pointer on devices that can hover.
// The server renders whole lines, so search engines, tests and assistive technology read the original text.
export function KineticTitle({lines,accent}:{lines:string[];accent:string}){
 const ref=useRef<HTMLHeadingElement>(null),calm=useCalm(),fine=useSyncExternalStore(finePointer.subscribe,finePointer.matches,()=>false),split=fine&&!calm,text=lines.join('\n');
 useEffect(()=>{const title=ref.current;if(!split||!title)return;const letters=[...title.querySelectorAll<HTMLElement>('.kt-char')];let frame=0;
  const move=(e:PointerEvent)=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{title.classList.add('is-live');for(const letter of letters){const r=letter.getBoundingClientRect(),near=Math.max(0,1-Math.hypot(e.clientX-r.left-r.width/2,e.clientY-r.top-r.height/2)/280);letter.style.setProperty('--kt-w',String(Math.round(250+650*near)));letter.style.setProperty('--kt-s',String(Math.round(100*near)));}});};
  const leave=()=>{cancelAnimationFrame(frame);title.classList.remove('is-live');};
  title.addEventListener('pointermove',move);title.addEventListener('pointerleave',leave);
  return()=>{cancelAnimationFrame(frame);title.classList.remove('is-live');title.removeEventListener('pointermove',move);title.removeEventListener('pointerleave',leave);};
 },[split,text]);
 const letters=(line:string)=>line.split(' ').map((word,i)=><Fragment key={i}>{i>0&&' '}<span className="kt-word">{Array.from(word).map((c,j)=><span className="kt-char" key={j}>{c}</span>)}</span></Fragment>);
 return <h1 ref={ref} className="kinetic-title" aria-label={split?[...lines,accent].join(' '):undefined}>{lines.map((line,i)=><Fragment key={i}><span className={'kt-line kt-line-'+(i+1)} aria-hidden={split||undefined}>{split?letters(line):line}</span><br/></Fragment>)}<em className="kt-line kt-accent" aria-hidden={split||undefined}>{accent}</em></h1>;
}
// The strip loops by repeating its items on the client only. Copies are hidden from assistive
// technology and skipped when reduced motion is requested; four groups cover wide screens.
export function Marquee({children}:{children:ReactNode}){
 const loop=!useCalm();
 return <div className={loop?'marquee is-looping':'marquee'}><div className="marquee-track"><div className="marquee-group">{children}</div>{loop&&[1,2,3].map(copy=><div className="marquee-group" aria-hidden="true" key={copy}>{children}</div>)}</div></div>;
}
