import {server,identity,unavailable,rpc} from '@/lib/supabase-server';
import {CloudError} from '@/lib/cloud-contract';
import assets from '@/lib/server/training-assets.json';
export const dynamic='force-dynamic';
export async function GET(req:Request,{params}:{params:Promise<{name:string}>}){
 let s;try{s=server(req);}catch{return unavailable();}try{
  await identity(s.client);const {name}=await params;
  if(!Object.prototype.hasOwnProperty.call(assets,name))throw new CloudError(404,'Image not found.');
  if(!await rpc(s.client,'evzon_training_asset',{p_name:name}))throw new CloudError(403,'This training image is not available to your account.');
  const raw=atob(assets[name as keyof typeof assets]);const bytes=Uint8Array.from(raw,c=>c.charCodeAt(0));
  s.headers.set('Content-Type','image/png');s.headers.set('Content-Disposition',`inline; filename="${name}"`);
  s.headers.set('Cross-Origin-Resource-Policy','same-origin');
  return new Response(bytes,{headers:s.headers});
 }catch(e){return s.fail(e);}
}
