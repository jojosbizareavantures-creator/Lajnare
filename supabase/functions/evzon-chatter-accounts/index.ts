import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
Deno.serve(async(req:Request)=>{
 const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');
  if(!token)return reply({error:'Sign in required'},401);
  const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const client=createClient(Deno.env.get('SUPABASE_URL')!,secret!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await client.auth.getUser(token);
  if(authError||!identity.user)return reply({error:'Sign in required'},401);
  const {data:profile}=await client.from('evzon_profiles').select('role,status').eq('id',identity.user.id).single();
  if(profile?.role!=='ADMIN'||profile?.status!=='Approved')return reply({error:'Admin access required'},403);
  const raw=await req.text();if(raw.length>8192)return reply({error:'Request too large'},413);
  const v=JSON.parse(raw);
  if(typeof v.name!=='string'||!v.name.trim()||v.name.length>100||typeof v.email!=='string'||!/^\S+@\S+\.\S+$/.test(v.email.trim())||v.email.length>254||typeof v.password!=='string'||v.password.length<12||v.password.length>256||typeof v.worker_id!=='string'||v.worker_id.length>100||typeof v.training_start!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(v.training_start)||!Number.isFinite(Date.parse(v.training_start)))return reply({error:'Check name, email, worker, start date and a password of at least 12 characters.'},422);
  const {data:workspace}=await client.from('evzon_workspace').select('state').eq('id',true).single();
  const worker=workspace?.state?.workers?.find((w:{id:string;status:string})=>w.id===v.worker_id&&w.status==='Training');
  if(!worker)return reply({error:'Choose an existing worker with Training status.'},422);
  const {data:existing}=await client.from('evzon_chatter_accounts').select('id').eq('worker_id',v.worker_id).maybeSingle();
  if(existing)return reply({error:'This worker already has a chatter account.'},409);
  // Auth may attach app metadata after INSERT; the database handles both events.
  const {data,error}=await client.auth.admin.createUser({email:v.email.trim().toLowerCase(),password:v.password,email_confirm:true,user_metadata:{name:v.name.trim()},app_metadata:{evzon_role:'CHATTER',worker_id:v.worker_id,training_start:v.training_start,created_by:identity.user.id}});
  if(error)return reply({error:error.code==='email_exists'?'An account already exists for this email. Use a different email.':'The account could not be created. Check the email and worker selection.'},422);
  // Never report successful creation before the account can enter the portal.
  const [enrollment,createdProfile]=await Promise.all([
   client.from('evzon_chatter_accounts').select('id,worker_id').eq('id',data.user.id).maybeSingle(),
   client.from('evzon_profiles').select('role,status').eq('id',data.user.id).single()
  ]);
  if(enrollment.error||createdProfile.error||enrollment.data?.worker_id!==v.worker_id||createdProfile.data?.role!=='CHATTER'||createdProfile.data?.status!=='Approved')return reply({error:'The login account was created, but portal setup did not finish. Contact your administrator before trying to create it again.'},500);
  return reply({id:data.user.id,message:'Chatter account created.'});
 }catch{return reply({error:'The account could not be created. Please try again.'},500);}
});


