import {server,identity,unavailable} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError,upstreamError} from '@/lib/cloud-contract';
export const dynamic='force-dynamic';
export async function GET(req:Request){
 let s;try{s=server(req);}catch{return unavailable();}
 try{
  const me=await identity(s.client,true);
  const [list,count]=await Promise.all([
   s.client.from('evzon_admin_notifications').select('id,application_id,referral_id,kind,candidate_name,created_at,read_at').eq('recipient_id',me.id).order('read_at',{ascending:true,nullsFirst:true}).order('created_at',{ascending:false}).limit(40),
   s.client.from('evzon_admin_notifications').select('id',{count:'exact',head:true}).eq('recipient_id',me.id).is('read_at',null)
  ]);
  if(list.error||count.error)throw upstreamError(list.error||count.error);
  return s.json({notifications:list.data,unread:count.count||0});
 }catch(e){return s.fail(e);}
}
export async function PATCH(req:Request){
 let s;try{s=server(req);}catch{return unavailable();}
 try{
  checkOrigin(req);const me=await identity(s.client,true),v=await readJson(req,4000);
  if(!Array.isArray(v.ids)||v.ids.length<1||v.ids.length>40||v.ids.some((id:unknown)=>typeof id!=='string'||!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(id)))throw new CloudError(422,'Choose the notifications to mark as read.');
  const {error}=await s.client.from('evzon_admin_notifications').update({read_at:new Date().toISOString()}).eq('recipient_id',me.id).in('id',v.ids).is('read_at',null);
  if(error)throw upstreamError(error);return s.json({ok:true});
 }catch(e){return s.fail(e);}
}
