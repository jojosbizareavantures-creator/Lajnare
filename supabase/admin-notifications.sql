-- Notifications are created in the same transaction as the application.
-- Each approved administrator has an independent read state.
create table public.evzon_admin_notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references public.evzon_profiles(id) on delete cascade,
 application_id uuid references public.evzon_applications(id) on delete cascade,
 referral_id uuid references public.evzon_referrals(id) on delete cascade,
 kind text not null check (kind in ('Application','Referral')),
 candidate_name text not null,
 created_at timestamptz not null default now(),
 read_at timestamptz,
 unique(recipient_id,application_id),
 unique(recipient_id,referral_id),
 check(application_id is not null or referral_id is not null)
);
create index notifications_recipient_created on public.evzon_admin_notifications(recipient_id,created_at desc);
create index notifications_unread on public.evzon_admin_notifications(recipient_id) where read_at is null;
alter table public.evzon_admin_notifications enable row level security;
revoke all on public.evzon_admin_notifications from public,anon,authenticated;
grant select,update(read_at) on public.evzon_admin_notifications to authenticated;
create policy notifications_admin_read on public.evzon_admin_notifications for select to authenticated
 using(recipient_id=(select auth.uid()) and (select evzon_private.is_admin()));
create policy notifications_admin_mark_read on public.evzon_admin_notifications for update to authenticated
 using(recipient_id=(select auth.uid()) and (select evzon_private.is_admin()))
 with check(recipient_id=(select auth.uid()) and (select evzon_private.is_admin()));

create function evzon_private.notify_new_referral() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.evzon_admin_notifications(recipient_id,referral_id,kind,candidate_name)
 select id,new.id,'Referral',new.candidate_name from public.evzon_profiles where role='ADMIN' and status='Approved';
 return new;
end $$;
create function evzon_private.notify_new_application() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.evzon_admin_notifications(recipient_id,application_id,referral_id,kind,candidate_name)
 select id,new.id,new.referral_id,'Application',new.first_name||' '||new.last_name
 from public.evzon_profiles where role='ADMIN' and status='Approved'
 on conflict(recipient_id,referral_id) do update set
  application_id=excluded.application_id,kind=excluded.kind,candidate_name=excluded.candidate_name,read_at=null;
 return new;
end $$;
revoke all on function evzon_private.notify_new_referral(),evzon_private.notify_new_application() from public,anon,authenticated;
create trigger notify_admin_application after insert on public.evzon_applications for each row execute function evzon_private.notify_new_application();
create trigger notify_admin_referral after insert on public.evzon_referrals for each row execute function evzon_private.notify_new_referral();
