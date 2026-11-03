import {server,rpc,unavailable} from '@/lib/supabase-server';
import {checkOrigin,readJson,CloudError} from '@/lib/cloud-contract';
import {ipAddress} from '@vercel/functions';
import {isIP} from 'node:net';
import {validateApplication,deviceInfo,signApplication,privacyVersion} from '@/lib/applications';
export async function POST(req:Request){let s;try{s=server(req);}catch{return unavailable();}try{
 checkOrigin(req);const v=await readJson(req,32_000);
 if(typeof v?.website==='string'&&v.website.trim())return s.json({submitted:true});
 let data;try{data=validateApplication(v);}catch(e){throw new CloudError(422,(e as Error).message);}
 const secret=process.env.APPLICATION_INGEST_SECRET;
 if(!secret)throw new CloudError(503,'Applications are temporarily unavailable. Please try again later.');
 // Vercel supplies this address. Locally, leave it unset instead of trusting a client header.
 const ip=process.env.VERCEL==='1'?(ipAddress(req)||''):'';
 const payload=JSON.stringify({data,meta:{...deviceInfo(req.headers.get('user-agent')||''),ip_address:isIP(ip)?ip:null,consent_version:privacyVersion},request_id:crypto.randomUUID(),sent_at:new Date().toISOString()});
 return s.json(await rpc(s.client,'evzon_submit_application',{p_payload:payload,p_signature:await signApplication(payload,secret)}));
 }catch(e){return s.fail(e);}}
