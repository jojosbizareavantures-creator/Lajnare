'use client';
import {useState} from 'react';
import {LearningReader} from './LearningReader';
import {PracticeExams} from './PracticeExams';
import {CheckCircle2,LockKeyhole,ArrowRight} from 'lucide-react';
import {useI18n} from '@/components/I18n';
import {Header,Card,Badge,Empty,Button} from '@/components/ui';
import {canStudy,nextTrainingStage,trainingAvailableOn,trainingLockReason,trainingStageLabel,type ChatterPortalData,type ChatterAccount} from '@/lib/chatter';
export type ChatterAction=(action:string,data:unknown)=>Promise<ChatterPortalData>;
export function TrainingHub({data,account,busy,act}:{data:ChatterPortalData;account:ChatterAccount;busy:boolean;act:ChatterAction}){
 const {t,language}=useI18n(),progress=data.progress.filter(p=>p.chatter_id===account.id),done=progress.filter(p=>p.status==='Approved').length;
 const [day,sd]=useState(()=>nextTrainingStage(account.id,progress)),[examPassed,setExamPassed]=useState(false),[chapter,setChapter]=useState(''),[studyReady,setStudyReady]=useState(false);
 const lesson=data.lessons.find(l=>l.day===day),p=progress.find(p=>p.day===day),lockReason=trainingLockReason(day,account,progress,data.today),unlocked=lockReason===null;
 const passed=!!account.hired_at||examPassed,examRequired=true,canContinue=passed;
 const lessonTitle=language==='mk'&&lesson?.title_mk?lesson.title_mk:lesson?.title||trainingStageLabel(day,t),lessonIntro=language==='mk'&&lesson?.content_mk?lesson.content_mk:lesson?.content||'';
 return <><Header title="Your training program" desc="Learn step by step, with your trainer alongside you."/>
 <div className="ch-training-summary"><div><span className="eyebrow">{t('YOUR TRAINING JOURNEY')}</span><h2>{done} / 7 <span>{t('stages approved')}</span></h2><p>{t(examRequired?'Learning materials → practice & exam → shadowing → CEO trial → your first shift.':'Learning materials → exam practice → shadowing → CEO trial → your first shift.')}</p></div><div className="ch-progress-ring" style={{background:'conic-gradient(var(--violet) '+done/7*360+'deg,var(--line) 0deg)'}}><span>{Math.round(done/7*100)}%</span></div></div>
 <div className="ch-training-layout"><nav className="ch-days" aria-label={t('Training stages')}>{data.lessons.map(l=>{const completed=progress.some(p=>p.day===l.day&&p.status==='Approved');return <button key={l.day} className={day===l.day?'selected':''} aria-current={day===l.day?'step':undefined} onClick={()=>{sd(l.day);setChapter('');setStudyReady(false);}}><span className={completed?'complete':''}>{completed?<CheckCircle2 size={18}/>:l.day}</span><div><b>{trainingStageLabel(l.day,t)}</b><small>{t(l.day<5?'Studying':l.day===5?l.published?'Exam preparation':'Being prepared':l.day===6?'Shadowing':'CEO trial shift')}</small></div>{!completed&&!canStudy(l.day,account,progress,data.today)&&<LockKeyhole size={15}/>}</button>})}</nav>
 <Card className="ch-lesson" title={lessonTitle} action={<Badge tone={p?.status==='Approved'?'green':'purple'}>{t(p?.status||'Not started')}</Badge>}>
 {!unlocked&&p?.status!=='Approved'?<div className="ch-lock"><LockKeyhole size={30}/><h3>{t('One step at a time')}</h3><p>{t(lockReason==='scheduled'?'This session opens on its scheduled date.':'Complete the previous stages and receive your trainer’s approval to continue.')}</p>{lockReason==='scheduled'&&<small>{t(day<=5?'Training begins':'Available from')}: {trainingAvailableOn(day,account.training_start)}</small>}</div>:<>
 {!lesson?.published?<Empty title={day===5?'Exam practice is being prepared':'Your study guide is being prepared'} desc={day===5?'Practice activities will appear here once your trainer adds them.':'Your trainer will publish the lesson here. You do not need to mark anything complete yet.'}/>:lessonIntro&&lessonIntro!==lessonTitle?<p className="ch-prose">{lessonIntro}</p>:null}
 {day<5&&lesson?.published&&<LearningReader key={day+'-'+chapter} initialUnit={chapter} day={day} chatterId={account.id} onReady={setStudyReady}/>}
 {day===5&&lesson?.published&&unlocked&&<PracticeExams onPassed={setExamPassed} onStudy={(stage,id)=>{sd(stage);setChapter(id);setStudyReady(false);}}/>}
 {day>=6&&canContinue&&lesson?.published&&data.config.discord_url&&<a className="btn" href={data.config.discord_url} target="_blank" rel="noopener noreferrer">{t('Open team Discord')}<ArrowRight size={16}/></a>}
 {p?.feedback&&<div className="ch-feedback"><b>{t('Trainer feedback')}</b><p className="ch-prose">{p.feedback}</p></div>}
 {p?.status==='Submitted'?<div className="info-banner">{t('Submitted. Your trainer will review this stage.')}</div>:p?.status!=='Approved'&&lesson?.published&&unlocked&&(day<5||canContinue)&&<Button primary disabled={busy||(day<5&&!studyReady)} onClick={()=>void act('submit-day',{day}).catch(()=>{})}>{t(day<5?'Submit material for trainer review':'Request trainer review')}<CheckCircle2 size={16}/></Button>}
 </>}</Card></div></>;
}

