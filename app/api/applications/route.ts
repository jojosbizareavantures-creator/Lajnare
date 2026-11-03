import {server,identity,rpc,unavailable} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError,upstreamError} from '@/lib/cloud-contract';
import {applicationStatuses} from '@/lib/applications';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 await identity(s.client,true);const params=new URL(req.url).searchParams,page=Number(params.get('page')||0),status=params.get('status')||'',q=(params.get('q')||'').trim(),id=params.get('id');
 if(id&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))throw new CloudError(422,'Application not found.');
 if(!Number.isSafeInteger(page)||page<0||page>100000||q.length>100||status&&!applicationStatuses.includes(status as any))throw new CloudError(422,'Check the search filters.');
 let query=s.client.from('evzon_applications').select('*',{count:'exact'}).order('created_at',{ascending:false}).order('id').range(page*50,page*50+49);
 if(status)query=query.eq('status',status);
 if(id)query=query.eq('id',id);
 if(q){const safe=q.replace(/[%_(),.\\"']/g,' ').replace(/\s+/g,' ').trim();if(safe)query=query.or(['first_name','last_name','email','country','city'].map(key=>`${key}.ilike.%${safe}%`).join(','));}
 const {data,count,error}=await query;if(error)throw upstreamError(error);return s.json({applications:data,total:count,page,pageSize:50});
 }catch(e){return s.fail(e);}}
export async function PATCH(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 checkOrigin(req);await identity(s.client,true);const v=await readJson(req,16_000);
 if(!v||typeof v.id!=='string'||!/^[0-9a-f-]{36}$/i.test(v.id)||!applicationStatuses.includes(v.status)||typeof v.admin_notes!=='string'||v.admin_notes.length>4000||typeof v.updated_at!=='string'||!Number.isFinite(Date.parse(v.updated_at)))throw new CloudError(422,'Check the review status and notes.');
 return s.json(await rpc(s.client,'evzon_review_application',{p_id:v.id,p_status:v.status,p_notes:v.admin_notes,p_updated_at:v.updated_at}));
 }catch(e){return s.fail(e);}}
