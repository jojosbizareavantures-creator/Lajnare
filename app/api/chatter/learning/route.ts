import {server,identity,unavailable,rpc} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError} from '@/lib/cloud-contract';
export const dynamic='force-dynamic';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{await identity(s.client);return s.json(await rpc(s.client,'evzon_training_portal'));}catch(e){return s.fail(e);}}
export async function POST(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 checkOrigin(req);await identity(s.client);const v=await readJson(req,150000);
 if(!v||!['read','edit-unit'].includes(v.action)||!v.data||typeof v.data!=='object'||Array.isArray(v.data))throw new CloudError(422,'Invalid training request.');
 return s.json(await rpc(s.client,'evzon_training_command',{p_action:v.action,p_data:v.data}));
 }catch(e){return s.fail(e);}}
