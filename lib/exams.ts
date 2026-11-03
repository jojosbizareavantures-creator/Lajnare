export type Bilingual={en:string;mk:string};
export type ExamOption={id:string;en:string;mk:string};
export type ExamQuestion={id:string;test_key:string;prompt:Bilingual;options:ExamOption[];correct?:string;explanation?:Bilingual;unit_id?:string;source_anchor?:string;source_title?:string;source_title_mk?:string;source_day?:number};
export type ExamAttempt={id:string;chatter_id:string;test_key:string;status:'In progress'|'Submitted';version:number;total:number;correct_count:number|null;score:number|null;passed:boolean|null;pass_score:number;started_at:string;submitted_at:string|null;feedback:string;reviewed_at:string|null;answers:Record<string,string>;questions:ExamQuestion[]};
export type ExamSummary={chatter_id:string;name:string;status:string;unlocked:boolean;graduated:boolean;practice_completed:string[];final_passed:boolean;permission:{id:string;note:string;granted_at:string}|null;active_attempt:string|null};
export type ExamsData={admin:boolean;settings:{pass_score:number};discord_url:string;summaries:ExamSummary[];attempts:Omit<ExamAttempt,'answers'|'questions'>[];attempt:ExamAttempt|null;bank:ExamQuestion[]};
export const practiceTests=[
 {key:'practice-1',title:{en:'Tools & foundations',mk:'Алатки и основи'}},
 {key:'practice-2',title:{en:'Conversation & decisions',mk:'Разговори и одлуки'}},
 {key:'practice-3',title:{en:'Timing & follow-ups',mk:'Соодветен момент и продолжување'}},
 {key:'practice-4',title:{en:'Daily operations & support',mk:'Дневни операции и поддршка'}},
 {key:'practice-5',title:{en:'Records & shift readiness',mk:'Евиденција и подготовка за смена'}}
] as const;
export const practiceCompleted=(s:ExamSummary)=>practiceTests.every(t=>s.practice_completed.includes(t.key));
export function finalEligibility(s:ExamSummary):'passed'|'locked'|'practice'|'awaiting'|'authorized'{return s.final_passed?'passed':!s.unlocked?'locked':!practiceCompleted(s)?'practice':s.permission?'authorized':'awaiting';}
export const testName=(key:string,lang:'en'|'mk')=>key==='final'?(lang==='mk'?'Завршен испит':'Final exam'):(lang==='mk'?'Тест за вежбање ':'Practice test ')+key.replace('practice-','');
export const testTitle=(key:string,lang:'en'|'mk')=>practiceTests.find(t=>t.key===key)?.title[lang]||testName(key,lang);
