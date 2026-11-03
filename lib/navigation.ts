import {chatterSections,chatterAdminSections} from './chatter';
import type {Profile} from './cloud-contract';
export const adminSections = ['chatters','calculator','workers','team','distribution','expenses','agencies','cash','schedule','recruitment','applications','breakeven','insights','reports','referrals','settings'] as const;
export const referrerSections = ['referrals','earnings','resources','activity','profile'] as const;
export const referralTabs = {pipeline:'Pipeline',rewards:'Rewards & payouts',accounts:'Accounts',performance:'Performance',program:'Program & resources',audit:'Audit'} as const;
export const landingPages = [
 {href:'/landing/how-it-works',label:'How it works'},
 {href:'/landing/earnings',label:'Salaries & earnings'},
 {href:'/landing/training',label:'Training'},
 {href:'/landing/referrals',label:'Refer & earn'},
 {href:'/landing/faq',label:'FAQ'},
] as const;
export function adminPath(page:string){return page==='overview'?'/adminpanel':'/adminpanel/'+page;}
export function referrerPath(page:string){return page==='overview'?'/referrer':'/referrer/'+page;}
export function profileHome(profile:Pick<Profile,'role'>){return profile.role==='CHATTER'?'/chatterportal':profile.role==='ADMIN'?'/adminpanel':'/referrer';}
export function canEnter(profile:Pick<Profile,'role'|'status'>|null,role:Profile['role']){return !!profile&&profile.role===role&&profile.status!=='Suspended'&&(role==='REFERRER'||profile.status==='Approved');}
// Only known internal destinations can be used after authentication.
export function loginDestination(profile:Pick<Profile,'role'>,next:string|null){
 const paths=profile.role==='CHATTER'?['/chatterportal',...chatterSections.map(x=>'/chatterportal/'+x)]:profile.role==='ADMIN'?['/adminpanel',...chatterAdminSections.map(x=>'/adminpanel/chatters/'+x),...adminSections.map(x=>adminPath(x)),...Object.keys(referralTabs).map(x=>'/adminpanel/referrals/'+x)]:['/referrer',...referrerSections.map(x=>referrerPath(x))];
 return next&&paths.includes(next)?next:profileHome(profile);
}
export function legacyEntry(query:Record<string,string|string[]|undefined>){return query.recovery!==undefined?'/reset-password':query.auth_error!==undefined?'/login?auth_error=1':'/landing';}
