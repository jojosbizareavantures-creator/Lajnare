'use client';
import {Fragment,useEffect,useRef,useState,type ReactNode} from 'react';
import {Expand,X,ZoomIn,ZoomOut,ImageOff} from 'lucide-react';
import {Button} from '@/components/ui';
import {useI18n} from '@/components/I18n';
import type {TrainingAsset,TrainingUnit} from '@/lib/training';

function inline(text:string):ReactNode[]{return text.split(/(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/g).map((v,i)=>v.startsWith('**')?<strong key={i}>{v.slice(2,-2)}</strong>:v.startsWith('*')?<em key={i}>{v.slice(1,-1)}</em>:v.startsWith('`')?<code key={i}>{v.slice(1,-1)}</code>:v);}
/** A deliberately small, safe renderer for the supplied notes: no HTML or executable links. */
export function LessonMarkdown({text,lang='en'}:{text:string;lang?:'en'|'mk'}){
 const lines=text.replace(/\r/g,'').split('\n'),nodes:ReactNode[]=[];let i=0;
 while(i<lines.length){const line=lines[i].trim();if(!line){i++;continue;}
  if(/^---+$/.test(line)){nodes.push(<hr key={i++}/>);continue;}
  const h=/^(#{1,6})\s+(.+)$/.exec(line);
  if(h){nodes.push(h[1].length<=2?<h3 key={i}>{inline(h[2])}</h3>:<h4 key={i}>{inline(h[2])}</h4>);i++;continue;}
  if(line.startsWith('|')&&i+1<lines.length&&/^\|[\s:|\-]+\|$/.test(lines[i+1].trim())){
   const cells=(s:string)=>s.trim().replace(/^\||\|$/g,'').split('|').map(c=>c.trim());const heads=cells(line),rows:string[][]=[];const key=i;i+=2;
   while(i<lines.length&&lines[i].trim().startsWith('|'))rows.push(cells(lines[i++]));
   nodes.push(<div className="learning-table" key={key}><table><thead><tr>{heads.map((c,j)=><th key={j}>{inline(c)}</th>)}</tr></thead><tbody>{rows.map((r,k)=><tr key={k}>{r.map((c,j)=><td key={j}>{inline(c)}</td>)}</tr>)}</tbody></table></div>);continue;
  }
  if(/^([-•]|\d+\.)\s/.test(line)){
   const ordered=/^\d+\./.test(line),start=parseInt(line),items:ReactNode[]=[];const key=i;
   while(i<lines.length&&((ordered?/^\d+\.\s/:/^[-•]\s/).test(lines[i].trim()))){const item=lines[i].trim();items.push(<li key={i++} value={ordered?parseInt(item):undefined}>{inline(item.replace(/^([-•]|\d+\.)\s+/,'').replace(/^\[ \]\s*/,''))}</li>);}
   nodes.push(ordered?<ol key={key} start={start}>{items}</ol>:<ul key={key}>{items}</ul>);continue;
  }
  if(line.startsWith('>')){nodes.push(<blockquote key={i++}>{inline(line.replace(/^>\s*/,''))}</blockquote>);continue;}
  const key=i,paragraph:string[]=[];
  while(i<lines.length&&lines[i].trim()&&!/^(#{1,6}\s|[-•]\s|\d+\.\s|\||---|>)/.test(lines[i].trim()))paragraph.push(lines[i++]);
  if(!paragraph.length){paragraph.push(lines[i++]);}
  nodes.push(<p key={key}>{paragraph.map((p,j)=><Fragment key={j}>{j>0&&<br/>}{inline(p)}</Fragment>)}</p>);
 }
 return <div className="learning-prose" lang={lang}>{nodes}</div>;
}
export function LessonContent({unit,assetUrl}:{unit:TrainingUnit;assetUrl?:(name:string)=>string}){
 const {language,t}=useI18n();
 return <>{unit.note&&<aside className="learning-note"><b>{t('Before you continue')}</b><p>{unit.note}</p></aside>}
 <LessonMarkdown text={language==='mk'&&unit.body_mk?unit.body_mk:unit.body} lang={language==='mk'&&unit.body_mk?'mk':'en'}/>
 {unit.assets.length>0&&<div className="learning-references"><h3>{t('Visual references')} <span>{unit.assets.length}</span></h3><p>{t('Original training images. Select an image to enlarge it.')} {language==='mk'&&t('Source images retain their original language.')}</p>{unit.assets.map(a=><ReferenceImage key={a.name} asset={{...a,title:t(a.title),caption:t(a.caption)}} assetUrl={assetUrl}/>)}</div>}</>;
}
function ReferenceImage({asset,assetUrl}:{asset:TrainingAsset;assetUrl?:(name:string)=>string}){
 const {t}=useI18n(),dialog=useRef<HTMLDialogElement>(null),[zoom,setZoom]=useState(100),[failed,setFailed]=useState(false);const src=assetUrl?assetUrl(asset.name):'/api/chatter/training-assets/'+encodeURIComponent(asset.name);
 useEffect(()=>()=>{dialog.current?.close();},[]);
 return <figure className="learning-reference"><figcaption><span className="learning-file">{asset.name}</span><b>{asset.title}</b></figcaption><p>{asset.caption}</p>
 {failed?<div className="learning-image-error"><ImageOff size={22}/>{t('Image could not load. Refresh your session and try again.')}<Button small onClick={()=>setFailed(false)}>{t('Retry')}</Button></div>:<button className="learning-image-button" aria-label={t('Enlarge image')+' '+asset.name} onClick={()=>{setZoom(100);dialog.current?.showModal();}}><img loading="lazy" src={src} alt={asset.title+' — '+asset.caption} onError={()=>setFailed(true)}/><span><Expand size={14}/>{t('Enlarge image')}</span></button>}
 <dialog ref={dialog} className="learning-image-dialog" aria-label={asset.title} onClick={e=>{if(e.target===e.currentTarget)dialog.current?.close();}}><div className="learning-image-tools"><div><b>{asset.title}</b><small>{asset.name}</small></div><div className="actions"><Button small aria-label={t('Zoom out')} disabled={zoom<=50} onClick={()=>setZoom(Math.max(50,zoom-25))}><ZoomOut size={17}/></Button><output>{zoom}%</output><Button small aria-label={t('Zoom in')} disabled={zoom>=300} onClick={()=>setZoom(Math.min(300,zoom+25))}><ZoomIn size={17}/></Button><Button small onClick={()=>setZoom(100)}>{t('Fit')}</Button><Button autoFocus aria-label={t('Close image')} onClick={()=>dialog.current?.close()}><X size={18}/></Button></div></div><div className="learning-image-canvas"><img src={src} alt={asset.title+' — '+asset.caption} style={{width:zoom+'%',maxWidth:'none'}}/></div><p>{asset.caption}</p></dialog>
 </figure>;
}
