import {server,unavailable} from '@/lib/supabase-server';
export const dynamic='force-dynamic';
export async function GET(req:Request){let s;try{s=server(req);}catch{return unavailable();}const u=new URL(req.url),code=u.searchParams.get('code'),token_hash=u.searchParams.get('token_hash'),type=u.searchParams.get('type');let error:any='Missing confirmation';
 if(code)({error}=await s.client.auth.exchangeCodeForSession(code));
 else if(token_hash&&(type==='email'||type==='recovery'))({error}=await s.client.auth.verifyOtp({token_hash,type}));
 const recovery=type==='recovery'||u.searchParams.has('recovery');const target=new URL(error?'/login?auth_error=1':recovery?'/reset-password':'/login',u.origin);
 s.headers.set('Location',target.href);s.headers.set('Referrer-Policy','no-referrer');return new Response(null,{status:303,headers:s.headers});}
