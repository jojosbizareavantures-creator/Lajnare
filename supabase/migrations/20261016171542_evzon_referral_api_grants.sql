-- Deliberately anonymous, write-only application endpoint. No caller-supplied referrer ID is accepted.
create function evzon_private.apply(p_code text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.evzon_profiles; rid uuid;
begin
 select * into p from public.evzon_profiles where code=upper(p_code) and status='Approved' and role='REFERRER';
 if p.id is null then raise exception 'EVZON_INVALID: Referral link is unavailable'; end if;
 if coalesce(p_data->>'website','')<>'' then return '{"submitted":true}'::jsonb; end if;
 if length(trim(coalesce(p_data->>'name',''))) not between 1 and 120 or coalesce(p_data->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_data->>'email')>254 or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'notes',''))>2000 or not coalesce((p_data->>'consent')::boolean,false) or not coalesce((p_data->>'adult')::boolean,false) then raise exception 'EVZON_INVALID: Complete the required fields and confirmations'; end if;
 perform pg_advisory_xact_lock(hashtext(p.id::text));
 if (select count(*) from public.evzon_referrals where referrer_id=p.id and created_at>now()-interval '1 day')>=30 then raise exception 'EVZON_INVALID: Submission limit reached; please try tomorrow'; end if;
 if exists(select 1 from evzon_private.contacts where email=lower(trim(p_data->>'email'))) then return '{"submitted":true}'::jsonb; end if;
 insert into public.evzon_referrals(referrer_id,candidate_name,source,terms) values(p.id,trim(p_data->>'name'),'Referral link',evzon_private.terms()) returning id into rid;
 insert into evzon_private.contacts(referral_id,email,phone,notes) values(rid,lower(trim(p_data->>'email')),coalesce(p_data->>'phone',''),coalesce(p_data->>'notes',''));
 insert into public.evzon_events(referrer_id,referral_id,message) values(p.id,rid,'New application received: '||trim(p_data->>'name'));
 return '{"submitted":true}'::jsonb;
exception when unique_violation then return '{"submitted":true}'::jsonb;
end $$;
create function public.evzon_portal() returns jsonb language sql security invoker set search_path='' as $$select evzon_private.portal();$$;
create function public.evzon_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select evzon_private.command(p_action,p_data);$$;
create function public.evzon_apply(p_code text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select evzon_private.apply(p_code,p_data);$$;
revoke execute on all functions in schema evzon_private from public,anon,authenticated;
revoke execute on function public.evzon_portal(),public.evzon_command(text,jsonb),public.evzon_apply(text,jsonb) from public,anon,authenticated;
grant execute on function evzon_private.is_admin(),evzon_private.is_approved(),evzon_private.portal(),evzon_private.command(text,jsonb) to authenticated;
grant usage on schema evzon_private to anon;
grant execute on function evzon_private.apply(text,jsonb) to anon,authenticated;
grant execute on function public.evzon_portal(),public.evzon_command(text,jsonb) to authenticated;
grant execute on function public.evzon_apply(text,jsonb) to anon,authenticated;
;
