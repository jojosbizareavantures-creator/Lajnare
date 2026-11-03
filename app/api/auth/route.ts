import {authRedirectUrl} from '@/lib/site-config';
import {server,identity,unavailable,rpc} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError,authFields} from '@/lib/cloud-contract';
export const dynamic='force-dynamic';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{return s.json({profile:await identity(s.client,false,true)});}catch(e){if(e instanceof CloudError&&e.status===401)return s.json({profile:null});return s.fail(e);}}
export async function POST(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{checkOrigin(req);const v=await readJson(req,8_192);if(!v||typeof v!=='object'||Array.isArray(v))throw new CloudError(422,'Invalid authentication request.');let error:any=null;let message='';
 if(v.action==='signin'){const fields=authFields(v);({error}=await s.client.auth.signInWithPassword(fields));if(!error&&v.portal==='chatter'){const p=await identity(s.client,false,true);if(p.role!=='CHATTER'){await s.client.auth.signOut();throw new CloudError(403,'Use your chatter account to sign in here.');}}}
 else if(v.action==='signup'){const fields=authFields(v,true);({error}=await s.client.auth.signUp({...fields,options:{data:{name:v.name.trim()},emailRedirectTo:authRedirectUrl(req)}}));message='Check your email to confirm your account. New referrer accounts require administrator approval.';}
 else if(v.action==='signout'){({error}=await s.client.auth.signOut());}
 else if(v.action==='resend'){if(typeof v.email!=='string'||v.email.length>254||!/^\S+@\S+\.\S+$/.test(v.email))throw new CloudError(422,'Enter a valid email.');({error}=await s.client.auth.resend({type:'signup',email:v.email.trim().toLowerCase(),options:{emailRedirectTo:authRedirectUrl(req)}}));message='If your account needs verification, a new confirmation email will arrive shortly. Check your spam folder too.';}
 else if(v.action==='reset'){if(typeof v.email!=='string'||v.email.length>254||!/^\S+@\S+\.\S+$/.test(v.email.trim()))throw new CloudError(422,'Enter a valid email.');({error}=await s.client.auth.resetPasswordForEmail(v.email.trim().toLowerCase(),{redirectTo:authRedirectUrl(req,true)}));message='If an account exists, a password-reset email will arrive shortly.';}
 else if(v.action==='password'){const p=await identity(s.client);if(typeof v.password!=='string'||v.password.length<12||v.password.length>256)throw new CloudError(422,'Use 12–256 characters.');({error}=await s.client.auth.updateUser({password:v.password}));if(!error&&p.role==='CHATTER')await rpc(s.client,'evzon_chatter_command',{p_action:'password-set',p_data:{}});message='Password updated.';}
 else throw new CloudError(422,'Unknown authentication action.');
 if(error)throw new CloudError(error.status===429?429:422,error.message);return s.json({ok:true,message});
 }catch(e){return s.fail(e);}}
