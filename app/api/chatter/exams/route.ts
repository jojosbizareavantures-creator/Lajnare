import {server,identity,unavailable,rpc} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError} from '@/lib/cloud-contract';
export const dynamic='force-dynamic';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 await identity(s.client);const id=new URL(req.url).searchParams.get('attempt');
 if(id&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))throw new CloudError(422,'Invalid attempt.');
 return s.json(await rpc(s.client,'evzon_exams_portal',{p_attempt:id||null}));
 }catch(e){return s.fail(e);}}
export async function POST(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 checkOrigin(req);await identity(s.client);const v=await readJson(req,30000);
 if(!v||!['start','save','submit','authorize','revoke','settings','feedback'].includes(v.action)||!v.data||typeof v.data!=='object'||Array.isArray(v.data))throw new CloudError(422,'Invalid exam request.');
 return s.json(await rpc(s.client,'evzon_exams_command',{p_action:v.action,p_data:v.data}));
 }catch(e){return s.fail(e);}}
