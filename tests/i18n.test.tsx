import {test} from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {I18nProvider,LanguageSelect} from '../components/I18n';
import {languageFrom,translateText,savedLanguage,saveLanguage,LANGUAGE_COOKIE,LANGUAGE_STORAGE} from '../lib/i18n';
import {Context} from '../components/store';
import {initial,calculate} from '../lib/finance';
import {Home} from '../components/marketing/Home';
import {HowItWorks} from '../components/marketing/HowItWorks';
import {Earnings} from '../components/marketing/Earnings';
import {Training} from '../components/marketing/Training';
import {Referrals} from '../components/marketing/Referrals';
import {FAQ} from '../components/marketing/FAQ';
import {MarketingShell} from '../components/marketing/MarketingShell';
import {PageLink} from '../components/marketing/PublicUI';
import {AuthForm} from '../components/Auth';
import {CandidateForm} from '../components/ReferrerPortal';
import {Dashboard,Insights} from '../components/Dashboard';
import {WorkerManager} from '../components/Workers';
import {TeamPayroll,ProfitDistribution} from '../components/Team';
import {RevenueCalculator,BreakEven} from '../components/Calculator';
import {ExpensesManager} from '../components/Expenses';
import {AgencyManager} from '../components/Agencies';
import {CashFlow} from '../components/Cash';
import {Schedule} from '../components/Schedule';
import {Recruitment} from '../components/Recruitment';
import {Reports} from '../components/Reports';
import {Settings} from '../components/Settings';
import {Editor,Slider} from '../components/ui';

const noop=()=>{};
function render(view:React.ReactNode,language:'en'|'mk'='mk',state=structuredClone(initial)){
 return renderToStaticMarkup(<I18nProvider initialLanguage={language}><Context.Provider value={{s:state,f:calculate(state),update:noop,save:noop,remove:noop,replace:noop,toast:noop,notice:''}}>{view}</Context.Provider></I18nProvider>);
}
const content=(html:string)=>html.replace(/<svg\b[\s\S]*?<\/svg>/g,'');
const englishText=(html:string)=>[...content(html).matchAll(/>([^<>]+)</g)].map(m=>m[1].trim()).filter(v=>/[a-zA-Z]{3}/.test(v)&&!/[Ѐ-ӿ]/.test(v));
const publicPages=[['home',<MarketingShell><Home/></MarketingShell>],['how it works',<HowItWorks/>],['earnings',<Earnings/>],['training',<Training/>],['referrals',<Referrals/>],['FAQ',<FAQ/>]] as const;
for(const [name,view] of publicPages)test('Macedonian public content is complete: '+name,()=>{
 const html=render(view);assert.match(html,/[Ѐ-ӿ]/);
 const unlocalized=englishText(html).filter(v=>!['EVZON','English','USD'].includes(v));assert.deepEqual(unlocalized,[]);
 const hrefs=(text:string)=>[...text.matchAll(/href="([^"]+)"/g)].map(m=>m[1]);assert.deepEqual(hrefs(html),hrefs(render(view,'en')));
});
const dashboardPages=[<Dashboard go={noop}/>,<Insights/>,<WorkerManager/>,<TeamPayroll/>,<ProfitDistribution/>,<RevenueCalculator/>,<BreakEven/>,<ExpensesManager/>,<AgencyManager/>,<CashFlow/>,<Schedule/>,<Recruitment/>,<Reports/>,<Settings/>];
test('all dashboard pages translate without changing names or financial records',()=>{
 const state=structuredClone(initial),before=JSON.stringify(state),figures=calculate(state);
 const allowed=new Set(['USD',...state.workers.map(w=>w.name),...state.team.map(t=>t.name),...state.expenses.map(e=>e.name)]);
 for(const page of dashboardPages){const html=render(page,'mk',state);assert.deepEqual(englishText(html).filter(t=>!allowed.has(t)),[]);assert.ok(!html.includes('NaN'));}
 assert.equal(JSON.stringify(state),before);assert.deepEqual(calculate(state),figures);
});
test('first-month pay and review conditions remain accurate in Macedonian',()=>{
 for(const page of [<Earnings/>,<Training/>]){const html=render(page);assert.ok(html.includes('Вашиот прв месец на работа во Evzon се плаќа $500.'));assert.ok(html.includes('Ако се подобрувате, можете да заработувате повеќе.'));assert.ok(html.includes('нема автоматски или фиксен иден износ'));}
 const home=render(<Home/>);assert.ok(!home.includes('$500'));
});
test('both language choices have fixed locale values and the requested selection',()=>{
 for(const [language,label] of [['en','Language'],['mk','Јазик']] as const){const html=render(<LanguageSelect/>,language);assert.ok(html.includes('aria-label="'+label+'"'));assert.ok(new RegExp('value="'+language+'"[^>]*selected').test(html));assert.equal((html.match(/<option/g)||[]).length,2);assert.ok(html.includes('English'));assert.ok(html.includes('Македонски'));}
});
test('login, registration, reset and application forms are translated with real destination links',()=>{
 for(const mode of ['signin','signup','reset'] as const){const html=render(<AuthForm mode={mode} refresh={async()=>{}}/>);assert.ok(html.includes('Назад кон веб-страницата'));assert.ok(html.includes('href="/landing"'));assert.ok(html.includes('Е-пошта'));assert.deepEqual(englishText(html).filter(v=>!['EVZON','English'].includes(v)),[]);}
 const candidate=render(<CandidateForm onSubmit={async()=>{}}/>);assert.ok(candidate.includes('Кандидатот има најмалку 18 години.'));assert.ok(candidate.includes('Поднеси пријава'));assert.ok(candidate.includes('type="email"'));
});
test('public back links use native anchors with no router click interception',()=>{
 const link=PageLink({href:'/landing',children:'Back'});assert.equal(link.type,'a');assert.equal(link.props.href,'/landing');assert.equal(link.props.onClick,undefined);
});
test('localized selectors preserve every English enum value for saving and filtering',()=>{
 const values=(html:string)=>[...html.matchAll(/<option[^>]*value="([^"]*)"/g)].map(m=>m[1]);
 const fields=[{key:'status',label:'Status',type:'select',options:['Training','Active','Inactive','Terminated']},{key:'payroll',label:'Worker payroll basis',type:'select',options:['Monthly salary','Approved hours']},{key:'agency',label:'Agency',type:'select',options:[{value:'',label:'Unassigned'},{value:'agency-active',label:'Active'}]}];
 const editor=<Editor title="Edit worker" row={{id:'one',name:'Communication quality',status:'Active',payroll:'Monthly salary'}} fields={fields} onSave={noop} onClose={noop}/>;
 for(const page of [...dashboardPages,editor])assert.deepEqual(values(render(page)),values(render(page,'en')));
 const html=render(editor);assert.ok(html.includes('value="Active" selected="">Активен'));assert.ok(html.includes('value="Approved hours">Одобрени часови'));assert.ok(html.includes('value="agency-active">Active'));assert.ok(html.includes('value="" selected="">Недоделено'));
});
test('translated slider label keeps the same numeric limits and values',()=>{
 const slider=<Slider label="Working days / month" value={26} max={31} onChange={noop}/>;
 const html=render(slider);assert.ok(html.includes('aria-label="Работни денови / месец"'));assert.ok(html.includes('aria-label="Работни денови / месец · лизгач"'));assert.equal((html.match(/max="31"/g)||[]).length,2);assert.equal((html.match(/value="26"/g)||[]).length,2);
});
test('calculated alerts translate their message while preserving exact figures',()=>{
 assert.equal(translateText('Your reserve target is 550.00 USD. Actual cash is 0.00 USD.','mk'),'Целната резерва е 550.00 USD. Реалната готовина е 0.00 USD.');
 assert.equal(translateText('$624 hourly · $0 commission','mk'),'$624 саатница · $0 провизија');
 assert.equal(translateText('Invalid login credentials','mk'),'Невалидни податоци за најава');
 assert.equal(translateText(700,'mk'),700);assert.equal(translateText('Independent name / ID-ABCD','mk'),'Independent name / ID-ABCD');
 assert.equal(translateText('constructor','mk'),'constructor');
});
test('language persistence survives reloads, supports switching back, and tolerates blocked storage',()=>{
 const storage=new Map<string,string>(),originals=new Map(['localStorage','document','location'].map(k=>[k,Object.getOwnPropertyDescriptor(globalThis,k)]));
 const doc={cookie:''};
 try{
  Object.defineProperty(globalThis,'document',{configurable:true,value:doc});Object.defineProperty(globalThis,'location',{configurable:true,value:{protocol:'https:'}});
  Object.defineProperty(globalThis,'localStorage',{configurable:true,value:{getItem:(k:string)=>storage.get(k)??null,setItem:(k:string,v:string)=>storage.set(k,v)}});
  saveLanguage('mk');assert.equal(savedLanguage(),'mk');assert.equal(storage.get(LANGUAGE_STORAGE),'mk');assert.ok(doc.cookie.includes(LANGUAGE_COOKIE+'=mk; Path=/;'));assert.ok(doc.cookie.includes('Secure'));assert.ok(doc.cookie.includes('SameSite=Lax'));
  saveLanguage('en');assert.equal(savedLanguage(),'en');assert.ok(doc.cookie.startsWith(LANGUAGE_COOKIE+'=en;'));
  storage.set(LANGUAGE_STORAGE,'unsupported');assert.equal(savedLanguage(),undefined);assert.equal(languageFrom('mk'),'mk');assert.equal(languageFrom('en'),'en');assert.equal(languageFrom('../admin'),undefined);
  Object.defineProperty(globalThis,'localStorage',{configurable:true,get(){throw new Error('Blocked');}});assert.equal(savedLanguage(),undefined);saveLanguage('mk');assert.ok(doc.cookie.startsWith(LANGUAGE_COOKIE+'=mk;'));
  Object.defineProperty(doc,'cookie',{configurable:true,set(){throw new Error('Blocked cookie');}});assert.doesNotThrow(()=>saveLanguage('en'));
 }finally{for(const [key,descriptor] of originals){if(descriptor)Object.defineProperty(globalThis,key,descriptor);else Reflect.deleteProperty(globalThis,key);}}
});
