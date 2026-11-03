import type {Profile} from './cloud-contract';
import type {Row} from './finance';
export type ChatterAccount={id:string;worker_id:string;training_start:string;completed_at:string|null;hired_at:string|null;must_change_password:boolean;created_at:string;name:string;email:string;status:Profile['status']};
export type Lesson={day:number;title:string;title_mk:string;content:string;content_mk:string;published:boolean};
export type Progress={id:string;chatter_id:string;day:number;status:'Submitted'|'Approved'|'Changes needed';feedback:string;submitted_at:string|null;approved_at:string|null};
export type Question={id:string;question:string;options:string[];correct?:number};
export type ChatterConfig={pass_score:number;max_attempts:number;exam_enabled:boolean;questions:Question[];discord_url:string};
export type Attempt={id:string;chatter_id:string;score:number;passed:boolean;created_at:string};
export type TimeEntry={id:string;chatter_id:string;shift_id:string|null;clock_in:string;clock_out:string|null;status:'Pending'|'Approved'|'Rejected';regular_hours:number;overtime_hours:number;notes:string};
export type ChatterPayout={id:string;chatter_id:string;period:string;amount:number;status:'Approved'|'Paid'|'Cancelled';notes:string;paid_at:string|null;reference:string;created_at:string};
export type Announcement={id:string;title:string;body:string;published:boolean;created_at:string};
export type ChatterPortalData={profile:Profile;accounts:ChatterAccount[];lessons:Lesson[];progress:Progress[];config:ChatterConfig;attempts:Attempt[];entries:TimeEntry[];payouts:ChatterPayout[];announcements:Announcement[];worker:Row|null;shifts:Row[];totals:{approved_due:number;paid:number;approved_month_hours:number};server_time:string;today:string};
export const chatterSections=['dashboard','training','clock','payouts','shifts','announcements','profile'] as const;
export const chatterAdminSections=['accounts','training','exams','exam','attendance','payouts','announcements'] as const;
export function trainingDay(start:string,today:string){return Math.max(0,Math.min(7,Math.floor((Date.parse(today+'T12:00:00Z')-Date.parse(start+'T12:00:00Z'))/86400000)+1));}
// Materials and exam preparation are approval-based. Live shadowing and the
// CEO trial retain their scheduled dates and the seven-day graduation boundary.
export function trainingAvailableOn(stage:number,start:string){
 const date=new Date(start+'T12:00:00Z');
 if(!Number.isInteger(stage)||stage<1||stage>7||Number.isNaN(date.getTime()))return '';
 date.setUTCDate(date.getUTCDate()+(stage<=5?0:stage-1));
 return date.toISOString().slice(0,10);
}
export function trainingLockReason(stage:number,account:ChatterAccount,progress:Progress[],today:string):'invalid'|'completed'|'previous'|'scheduled'|null{
 const available=trainingAvailableOn(stage,account.training_start);
 if(!available||!/^\d{4}-\d{2}-\d{2}$/.test(today))return 'invalid';
 if(account.completed_at)return 'completed';
 if(Array.from({length:stage-1},(_,i)=>i+1).some(n=>!progress.some(p=>p.chatter_id===account.id&&p.day===n&&p.status==='Approved')))return 'previous';
 return today<available?'scheduled':null;
}
export function canStudy(stage:number,account:ChatterAccount,progress:Progress[],today:string){return trainingLockReason(stage,account,progress,today)===null;}
export function nextTrainingStage(accountId:string,progress:Progress[]){return [1,2,3,4,5,6,7].find(stage=>!progress.some(p=>p.chatter_id===accountId&&p.day===stage&&p.status==='Approved'))??7;}
export function trainingStageLabel(stage:number,t:(value:string)=>string=(value)=>value){return stage<=4?t('Learning material')+' '+stage:stage===5?t('Practicing for exams'):t('Day')+' '+stage;}
export function elapsedHours(entry:TimeEntry,now=Date.now()){return Math.max(0,((entry.clock_out?Date.parse(entry.clock_out):now)-Date.parse(entry.clock_in))/3600000);}
export function shiftEnd(shift:Row){const [h,m]=String(shift.start).split(':').map(Number);const end=Math.round(h*60+m+Number(shift.scheduled)*60)%1440;return String(Math.floor(end/60)).padStart(2,'0')+':'+String(end%60).padStart(2,'0');}
export function localMonth(timestamp:string){const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Skopje',year:'numeric',month:'2-digit'}).formatToParts(new Date(timestamp));return parts.find(p=>p.type==='year')!.value+'-'+parts.find(p=>p.type==='month')!.value;}

