-- Direct candidate applications. Contact and device data are readable only by approved admins.
create table public.evzon_applications (
 id uuid primary key,
 first_name text not null check(length(first_name) between 1 and 60),
 last_name text not null check(length(last_name) between 1 and 60),
 country text not null check(length(country) between 1 and 80),
 city text not null check(length(city) between 1 and 100),
 date_of_birth date not null check(date_of_birth >= date '1900-01-01'),
 age_at_submission integer not null check(age_at_submission >= 18),
 phone text not null check(length(phone) between 7 and 40),
 email text not null check(length(email)<=254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
 gender text not null check(gender in ('M','F')),
 equipment text not null check(equipment in ('Desktop PC','Laptop','Desktop PC and laptop')),
 message text not null default '' check(length(message)<=2000),
 experience text not null default '' check(length(experience)<=1000),
 availability text not null default '' check(length(availability)<=300),
 language text not null check(language in ('en','mk')),
 referral_id uuid references public.evzon_referrals(id) on delete set null,
 referral_code text not null default '',
 consent_version text not null,
 ip_address inet,
 user_agent text not null check(length(user_agent)<=1000),
 browser text not null,os text not null,device_type text not null,
 status text not null default 'New' check(status in ('New','Under review','Contacted','Interview','Accepted','Rejected','Archived')),
 admin_notes text not null default '' check(length(admin_notes)<=4000),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index applications_created on public.evzon_applications(created_at desc,id);
create index applications_status_created on public.evzon_applications(status,created_at desc);
create index applications_email on public.evzon_applications(email,created_at desc);
create index applications_ip on public.evzon_applications(ip_address,created_at desc);
create index applications_referral on public.evzon_applications(referral_id);
alter table public.evzon_applications enable row level security;
revoke all on public.evzon_applications from public,anon,authenticated;
grant select on public.evzon_applications to authenticated;
create policy applications_admin_read on public.evzon_applications for select to authenticated using((select evzon_private.is_admin()));

-- The server secret signs only validated application submissions. It grants no read or admin access.
create table evzon_private.application_ingest_config(id boolean primary key default true check(id),secret text not null);
insert into evzon_private.application_ingest_config(id,secret) values(true,encode(extensions.gen_random_bytes(32),'hex'));
alter table evzon_private.application_ingest_config enable row level security;
revoke all on evzon_private.application_ingest_config from public,anon,authenticated;

create function evzon_private.submit_application(p_payload text,p_signature text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v jsonb;d jsonb;m jsonb;k text;req uuid;ip inet;birth date;years integer;rid uuid;pid uuid;mail text;refcode text;
begin
 if p_payload is null or octet_length(p_payload)>32000 or p_signature is null or p_signature !~ '^[0-9a-f]{64}$' then raise exception 'EVZON_FORBIDDEN';end if;
 select secret into k from evzon_private.application_ingest_config where id;
 if k is null or encode(extensions.hmac(p_payload,k,'sha256'),'hex')<>p_signature then raise exception 'EVZON_FORBIDDEN';end if;
 v:=p_payload::jsonb;d:=v->'data';m:=v->'meta';req:=(v->>'request_id')::uuid;
 if v->>'sent_at' is null or abs(extract(epoch from (now()-(v->>'sent_at')::timestamptz)))>300 then raise exception 'EVZON_FORBIDDEN';end if;
 if req is null or d is null or m is null then raise exception 'EVZON_INVALID: Check your application details.';end if;
 if exists(select 1 from public.evzon_applications where id=req) then return '{"submitted":true}'::jsonb;end if;
 if not coalesce((d->>'adult')::boolean,false) or not coalesce((d->>'consent')::boolean,false) then raise exception 'EVZON_INVALID: Confirm the age requirement and application privacy notice.';end if;
 birth:=(d->>'date_of_birth')::date;
 years:=extract(year from age((now() at time zone 'Europe/Skopje')::date,birth));
 if birth is null or birth<date '1900-01-01' or years<18 then raise exception 'EVZON_INVALID: You must be at least 18 to apply.';end if;
 if d->>'phone' !~ '^\+?[0-9 ().-]+$' or length(regexp_replace(d->>'phone','[^0-9]','','g')) not between 7 and 15 then raise exception 'EVZON_INVALID: Enter a valid phone number, including your country code.';end if;
 mail:=lower(trim(d->>'email'));refcode:=upper(coalesce(d->>'code',''));ip:=nullif(m->>'ip_address','')::inet;
 -- Locks make email deduplication and IP limits safe under concurrent submissions.
 if ip is not null then
  perform pg_advisory_xact_lock(hashtext('application-ip:'||ip::text));
  if (select count(*) from public.evzon_applications where ip_address=ip and created_at>now()-interval '1 hour')>=5
   or (select count(*) from public.evzon_applications where ip_address=ip and created_at>now()-interval '1 day')>=20 then raise exception 'EVZON_INVALID: Too many applications. Please try again later.';end if;
 end if;
 perform pg_advisory_xact_lock(hashtext('application-email:'||mail));
 if exists(select 1 from public.evzon_applications where email=mail and created_at>now()-interval '1 day') then return '{"submitted":true}'::jsonb;end if;
 if refcode<>'' then
  select id into pid from public.evzon_profiles where public.evzon_profiles.code=refcode and status='Approved' and role='REFERRER';
  if pid is null then raise exception 'EVZON_INVALID: Check the referral code, or leave it empty to apply directly.';end if;
  perform evzon_private.apply(refcode,jsonb_build_object('name',left(trim(d->>'first_name')||' '||trim(d->>'last_name'),120),'email',mail,'phone',d->>'phone','notes',d->>'message','adult',true,'consent',true));
  select r.id into rid from public.evzon_referrals r join evzon_private.contacts c on c.referral_id=r.id where c.email=mail and r.referrer_id=pid;
 end if;
 insert into public.evzon_applications(id,first_name,last_name,country,city,date_of_birth,age_at_submission,phone,email,gender,equipment,message,experience,availability,language,referral_id,referral_code,consent_version,ip_address,user_agent,browser,os,device_type)
 values(req,trim(d->>'first_name'),trim(d->>'last_name'),trim(d->>'country'),trim(d->>'city'),birth,years,trim(d->>'phone'),mail,d->>'gender',d->>'equipment',coalesce(d->>'message',''),coalesce(d->>'experience',''),coalesce(d->>'availability',''),d->>'language',rid,case when rid is null then '' else refcode end,m->>'consent_version',ip,m->>'user_agent',m->>'browser',m->>'os',m->>'device_type');
 return '{"submitted":true}'::jsonb;
end $$;
create function public.evzon_submit_application(p_payload text,p_signature text) returns jsonb language sql security invoker set search_path='' as $$select evzon_private.submit_application(p_payload,p_signature);$$;
revoke all on function evzon_private.submit_application(text,text),public.evzon_submit_application(text,text) from public,anon,authenticated;
grant execute on function evzon_private.submit_application(text,text),public.evzon_submit_application(text,text) to anon,authenticated;

create function evzon_private.review_application(p_id uuid,p_status text,p_notes text,p_updated_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old public.evzon_applications;result public.evzon_applications;
begin
 if auth.uid() is null or not evzon_private.is_admin() then raise exception 'EVZON_FORBIDDEN';end if;
 select * into old from public.evzon_applications where id=p_id for update;
 if not found then raise exception 'EVZON_INVALID: Application not found.';end if;
 if p_updated_at is null or old.updated_at<>p_updated_at then raise exception 'EVZON_CONFLICT';end if;
 update public.evzon_applications set status=p_status,admin_notes=p_notes,updated_at=clock_timestamp() where id=p_id returning * into result;
 perform evzon_private.audit('Application reviewed',jsonb_build_object('id',old.id,'status',old.status,'admin_notes',old.admin_notes),jsonb_build_object('id',result.id,'status',result.status,'admin_notes',result.admin_notes));
 return to_jsonb(result);
end $$;
create function public.evzon_review_application(p_id uuid,p_status text,p_notes text,p_updated_at timestamptz) returns jsonb language sql security invoker set search_path='' as $$select evzon_private.review_application(p_id,p_status,p_notes,p_updated_at);$$;
revoke all on function evzon_private.review_application(uuid,text,text,timestamptz),public.evzon_review_application(uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function evzon_private.review_application(uuid,text,text,timestamptz),public.evzon_review_application(uuid,text,text,timestamptz) to authenticated;
;
