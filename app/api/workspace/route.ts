import {server,identity,rpc,unavailable} from '@/lib/supabase-server';
import {checkOrigin,readJson,validateSave,upstreamError} from '@/lib/cloud-contract';
export const dynamic='force-dynamic';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{await identity(s.client,true);const w=await s.client.from('evzon_workspace').select('*').eq('id',true).single();if(w.error)throw upstreamError(w.error);const portal=await rpc(s.client,'evzon_portal');return s.json({workspace:w.data,portal});}catch(e){return s.fail(e);}}
export async function PUT(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{checkOrigin(req);await identity(s.client,true);const v=validateSave(await readJson(req));const portal=await rpc(s.client,'evzon_command',{p_action:'save',p_data:v});return s.json({workspace:portal.workspace,portal});}catch(e){return s.fail(e);}}
