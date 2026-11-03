import {server,identity,unavailable,rpc} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError} from '@/lib/cloud-contract';
export const dynamic='force-dynamic';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{await identity(s.client);return s.json(await rpc(s.client,'evzon_chatter_portal'));}catch(e){return s.fail(e);}}
export async function POST(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 checkOrigin(req);const v=await readJson(req,150000);if(!v||typeof v.action!=='string'||!v.data||typeof v.data!=='object'||Array.isArray(v.data))throw new CloudError(422,'Invalid chatter request.');
 const profile=await identity(s.client);
 if(v.action==='create-account'){
  if(profile.role!=='ADMIN'||profile.status!=='Approved')throw new CloudError(403,'Admin access required.');
  const {data,error}=await s.client.functions.invoke('evzon-chatter-accounts',{body:v.data});
  if(error){let message='The account could not be created. Please try again.';try{const body=await error.context?.json();if(body?.error)message=body.error;}catch{}throw new CloudError(422,message);}
  if(data?.error)throw new CloudError(422,data.error);
  return s.json(await rpc(s.client,'evzon_chatter_portal'));
 }
 if(v.action==='password'){
  if(profile.role!=='CHATTER')throw new CloudError(403,'Chatter access only.');
  if(typeof v.data.password!=='string'||v.data.password.length<12||v.data.password.length>256)throw new CloudError(422,'Use 12–256 characters.');
  const {error}=await s.client.auth.updateUser({password:v.data.password});if(error)throw new CloudError(422,error.message);
  return s.json(await rpc(s.client,'evzon_chatter_command',{p_action:'password-set',p_data:{}}));
 }
 return s.json(await rpc(s.client,'evzon_chatter_command',{p_action:v.action,p_data:v.data}));
 }catch(e){return s.fail(e);}}

