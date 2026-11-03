const KEY='evzon.referral-link';
const MAX_AGE=30*24*60*60*1000;
export function rememberReferral(code:string,now=Date.now()){
 try{if(/^[A-Z0-9]{12}$/i.test(code))localStorage.setItem(KEY,JSON.stringify({code:code.toUpperCase(),at:now}));else localStorage.removeItem(KEY);}catch{/* Attribution still travels in the visible form when storage is unavailable. */}
}
export function rememberedReferral(now=Date.now()){
 try{const value=JSON.parse(localStorage.getItem(KEY)||'null');if(value&&/^[A-Z0-9]{12}$/.test(value.code)&&typeof value.at==='number'&&now>=value.at&&now-value.at<MAX_AGE)return value.code as string;localStorage.removeItem(KEY);}catch{/* No hidden or required tracking state. */}
 return '';
}
