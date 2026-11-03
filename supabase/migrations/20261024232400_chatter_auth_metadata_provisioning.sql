-- Supabase can attach trusted app metadata after the initial auth.users INSERT.
-- Provision on that UPDATE as well, without changing existing portal access.
create or replace function evzon_private.profile_created()
returns trigger language plpgsql security definer set search_path='' as $$
declare w jsonb;
begin
 insert into public.evzon_profiles(id,name,email)
 values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''),split_part(new.email,'@',1),'Referrer'),100),coalesce(new.email,''))
 on conflict(id) do update set email=excluded.email;
 if new.raw_app_meta_data->>'evzon_role'='CHATTER' then
  perform pg_advisory_xact_lock(782541);
  if not exists(select 1 from public.evzon_chatter_accounts where id=new.id) then
   if not exists(select 1 from public.evzon_profiles where id=(new.raw_app_meta_data->>'created_by')::uuid and role='ADMIN' and status='Approved') then
    raise exception 'EVZON_FORBIDDEN';
   end if;
   if not exists(select 1 from public.evzon_profiles where id=new.id and role='REFERRER' and status='Pending') then
    raise exception 'EVZON_INVALID: This account cannot be automatically provisioned as a chatter';
   end if;
   select x into w from public.evzon_workspace,jsonb_array_elements(state->'workers') x
    where x->>'id'=new.raw_app_meta_data->>'worker_id';
   if w is null or w->>'status'<>'Training' then
    raise exception 'EVZON_INVALID: Select a worker with Training status';
   end if;
   update public.evzon_profiles set role='CHATTER',status='Approved' where id=new.id;
   insert into public.evzon_chatter_accounts(id,worker_id,training_start,created_by)
    values(new.id,w->>'id',(new.raw_app_meta_data->>'training_start')::date,(new.raw_app_meta_data->>'created_by')::uuid);
   insert into evzon_private.chatter_passwords values(new.id,new.encrypted_password);
   insert into evzon_private.audit(actor,action,after_data)
    values((new.raw_app_meta_data->>'created_by')::uuid,'Chatter account provisioned',
     jsonb_build_object('account_id',new.id,'worker_id',w->>'id'));
  end if;
 elsif new.email_confirmed_at is not null and exists(select 1 from evzon_private.admin_bootstrap where email=lower(new.email)) then
  update public.evzon_profiles set role='ADMIN',status='Approved' where id=new.id;
  delete from evzon_private.admin_bootstrap where email=lower(new.email);
 end if;
 return new;
end $$;
drop trigger evzon_profile_created on auth.users;
create trigger evzon_profile_created
after insert or update of email_confirmed_at,email,raw_app_meta_data on auth.users
for each row execute function evzon_private.profile_created();
;
