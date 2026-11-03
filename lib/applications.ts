// Shared, deterministic validation. Never trust a browser-supplied age, role or IP.
export const applicationStatuses=['New','Under review','Contacted','Interview','Accepted','Rejected','Archived'] as const;
export const equipmentOptions=['Desktop PC','Laptop','Desktop PC and laptop'] as const;
export const privacyVersion='2026-10-18';
export function todayInSkopje(now=new Date()){
 // Locale output ordering differs between browser/ICU releases. Build ISO from
 // named parts so age validation always compares YYYY-MM-DD calendar dates.
 const parts=new Intl.DateTimeFormat('en',{timeZone:'Europe/Skopje',calendar:'gregory',numberingSystem:'latn',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
 const value=(type:string)=>parts.find(part=>part.type===type)!.value;
 return `${value('year')}-${value('month')}-${value('day')}`;
}
export function ageOn(dob:string,today=todayInSkopje()):number|null{
 if(!/^\d{4}-\d{2}-\d{2}$/.test(dob))return null;
 const d=new Date(dob+'T00:00:00Z');if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==dob||dob>today||dob<'1900-01-01')return null;
 const [y,m,day]=dob.split('-').map(Number),[ty,tm,td]=today.split('-').map(Number);return ty-y-(tm<m||tm===m&&td<day?1:0);
}
export type ApplicationInput={first_name:string;last_name:string;country:string;city:string;date_of_birth:string;phone:string;email:string;gender:string;equipment:string;message:string;experience:string;availability:string;code:string;adult:boolean;consent:boolean;language:'en'|'mk';website:string};
export const blankApplication:ApplicationInput={first_name:'',last_name:'',country:'',city:'',date_of_birth:'',phone:'',email:'',gender:'',equipment:'',message:'',experience:'',availability:'',code:'',adult:false,consent:false,language:'en',website:''};
export function validateApplication(value:unknown,today=todayInSkopje()):ApplicationInput{
 if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Check your application details.');
 const v=value as Record<string,unknown>;
 const text=(key:string,max:number,required=false)=>{const s=typeof v[key]==='string'?(v[key] as string).trim():'';if(s.length>max||required&&!s||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(s))throw new Error('Check the required fields and text lengths.');return s;};
 const d={...blankApplication,first_name:text('first_name',60,true),last_name:text('last_name',60,true),country:text('country',80,true),city:text('city',100,true),date_of_birth:text('date_of_birth',10,true),phone:text('phone',40,true),email:text('email',254,true).toLowerCase(),gender:text('gender',1,true),equipment:text('equipment',30,true),message:text('message',2000),experience:text('experience',1000),availability:text('availability',300),code:text('code',12).toUpperCase(),adult:v.adult===true,consent:v.consent===true,language:v.language==='mk'?'mk' as const:'en' as const,website:text('website',300)};
 if(!/^\S+@[^\s@]+\.[^\s@]+$/.test(d.email))throw new Error('Enter a valid email.');
 if(!/^\+?[\d ()\-.]+$/.test(d.phone)||d.phone.replace(/\D/g,'').length<7||d.phone.replace(/\D/g,'').length>15)throw new Error('Enter a valid phone number, including your country code.');
 const age=ageOn(d.date_of_birth,today);if(age===null)throw new Error('Enter a valid date of birth.');if(age<18)throw new Error('You must be at least 18 to apply.');
 if(!equipmentOptions.includes(d.equipment as typeof equipmentOptions[number]))throw new Error('A desktop PC or laptop is required.');
 if(!['M','F'].includes(d.gender))throw new Error('Select your gender.');
 if(d.code&&!/^[A-Z0-9]{12}$/.test(d.code))throw new Error('Check the referral code, or leave it empty to apply directly.');
 if(!d.adult||!d.consent)throw new Error('Confirm the age requirement and application privacy notice.');return d;
}
export function deviceInfo(userAgent:string){
 const ua=userAgent.slice(0,1000);
 const browser=/Edg\//.test(ua)?'Microsoft Edge':/OPR\//.test(ua)?'Opera':/Firefox\/|FxiOS\//.test(ua)?'Firefox':/Chrome\/|CriOS\//.test(ua)?'Chrome':/Safari\//.test(ua)?'Safari':'Unknown';
 const os=/Android/.test(ua)?'Android':/iPhone|iPad|iPod/.test(ua)?'iOS / iPadOS':/Windows/.test(ua)?'Windows':/Mac OS X|Macintosh/.test(ua)?'macOS':/Linux/.test(ua)?'Linux':'Unknown';
 const device=/iPad|Tablet/.test(ua)||/Android/.test(ua)&&!/Mobile/.test(ua)?'Tablet':/Mobi|iPhone|iPod/.test(ua)?'Mobile':/Windows|Macintosh|Linux/.test(ua)?'Desktop / laptop':'Unknown';
 return {user_agent:ua,browser,os,device_type:device};
}
export async function signApplication(payload:string,secret:string){
 const encoder=new TextEncoder(),key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(payload)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
export type ApplicationRecord=Omit<ApplicationInput,'adult'|'website'|'consent'|'code'> & {id:string;created_at:string;updated_at:string;age_at_submission:number;ip_address:string|null;user_agent:string;browser:string;os:string;device_type:string;status:typeof applicationStatuses[number];admin_notes:string;referral_id:string|null;referral_code:string;consent_version:string};
