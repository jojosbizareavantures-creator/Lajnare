create function evzon_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.evzon_profiles where id=auth.uid() and role='ADMIN' and status='Approved');$$;
create function evzon_private.is_approved() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.evzon_profiles where id=auth.uid() and status='Approved');$$;
create function evzon_private.profile_created() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.evzon_profiles(id,name,email) values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''),split_part(new.email,'@',1),'Referrer'),100),coalesce(new.email,'')) on conflict(id) do update set email=excluded.email;
 if new.email_confirmed_at is not null and exists(select 1 from evzon_private.admin_bootstrap where email=lower(new.email)) then
  update public.evzon_profiles set role='ADMIN',status='Approved' where id=new.id;
  delete from evzon_private.admin_bootstrap where email=lower(new.email);
 end if;
 return new;
end $$;
create trigger evzon_profile_created after insert or update of email_confirmed_at,email on auth.users for each row execute function evzon_private.profile_created();
alter table public.evzon_profiles enable row level security;
alter table public.evzon_workspace enable row level security;
alter table public.evzon_referral_config enable row level security;
alter table public.evzon_referrals enable row level security;
alter table public.evzon_rewards enable row level security;
alter table public.evzon_events enable row level security;
alter table evzon_private.contacts enable row level security;
alter table evzon_private.admin_bootstrap enable row level security;
alter table evzon_private.audit enable row level security;
alter table evzon_private.periods enable row level security;
alter table evzon_private.workday_exceptions enable row level security;
alter table evzon_private.payouts enable row level security;
revoke all on all tables in schema evzon_private from public,anon,authenticated;
revoke all on public.evzon_profiles,public.evzon_workspace,public.evzon_referral_config,public.evzon_referrals,public.evzon_rewards,public.evzon_events from public,anon,authenticated;
grant select on public.evzon_profiles,public.evzon_workspace,public.evzon_referral_config,public.evzon_referrals,public.evzon_rewards,public.evzon_events to authenticated;
create policy profile_read on public.evzon_profiles for select to authenticated using(id=(select auth.uid()) or (select evzon_private.is_admin()));
create policy workspace_read on public.evzon_workspace for select to authenticated using((select evzon_private.is_admin()));
create policy config_read on public.evzon_referral_config for select to authenticated using((select auth.uid()) is not null);
create policy referrals_read on public.evzon_referrals for select to authenticated using((select evzon_private.is_admin()) or (referrer_id=(select auth.uid()) and (select evzon_private.is_approved())));
create policy rewards_read on public.evzon_rewards for select to authenticated using((select evzon_private.is_admin()) or (referrer_id=(select auth.uid()) and (select evzon_private.is_approved())));
create policy events_read on public.evzon_events for select to authenticated using((select evzon_private.is_admin()) or (referrer_id=(select auth.uid()) and (select evzon_private.is_approved())));
create function evzon_private.terms() returns jsonb language sql stable set search_path='' as $$select to_jsonb(c)-'id'-'resources'-'updated_at' from public.evzon_referral_config c where id;$$;
create function evzon_private.audit(p_action text,p_before jsonb default null,p_after jsonb default null) returns void language sql set search_path='' as $$insert into evzon_private.audit(actor,action,before_data,after_data) values(auth.uid(),p_action,p_before,p_after);$$;
create function evzon_private.collected(p_worker text,p_period date) returns boolean language plpgsql stable set search_path='' as $$
declare p evzon_private.periods; s jsonb; inv text; total numeric; paid numeric;
begin
 select * into p from evzon_private.periods where worker_id=p_worker and period=p_period;
 if not found or cardinality(p.invoices)=0 then return false; end if;
 select state into s from public.evzon_workspace where id;
 foreach inv in array p.invoices loop
  select (x->>'amount')::numeric into total from jsonb_array_elements(s->'invoices') x where x->>'id'=inv;
  if total is null then return false; end if;
  select coalesce(sum((x->>'amount')::numeric),0) into paid from jsonb_array_elements(s->'payments') x where x->>'invoice'=inv and (x->>'date')::date<=current_date;
  if paid<total then return false; end if;
 end loop;
 return true;
end $$;

revoke execute on all functions in schema evzon_private from public,anon,authenticated;
grant execute on function evzon_private.is_admin(),evzon_private.is_approved() to authenticated;
;
