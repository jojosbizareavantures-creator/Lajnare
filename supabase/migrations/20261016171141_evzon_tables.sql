-- Evzon baseline, applied using the Supabase migration API.
-- Only user JWTs are used by the app; no service-role key.
create schema if not exists evzon_private;
revoke all on schema evzon_private from public,anon;
grant usage on schema evzon_private to authenticated;
create table evzon_private.admin_bootstrap(email text primary key);
insert into evzon_private.admin_bootstrap values('jojosbizareavantures@gmail.com');
create table public.evzon_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 100), email text not null,
 role text not null default 'REFERRER' check(role in ('ADMIN','REFERRER')),
 status text not null default 'Pending' check(status in ('Pending','Approved','Suspended')),
 code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
 payout_preference text not null default '' check(length(payout_preference)<=200),created_at timestamptz not null default now()
);
create table public.evzon_workspace(id boolean primary key default true check(id),state jsonb,revision bigint not null default 0,updated_at timestamptz not null default now(),updated_by uuid references public.evzon_profiles(id));
insert into public.evzon_workspace(id) values(true);
create table public.evzon_referral_config (
 id boolean primary key default true check(id),hire_bonus numeric not null default 20 check(hire_bonus between 0 and 100000),
 retention_bonus numeric not null default 30 check(retention_bonus between 0 and 100000),retention_days int not null default 30 check(retention_days between 1 and 365),
 commission_rate numeric not null default 5 check(commission_rate between 0 and 100),commission_months int not null default 6 check(commission_months between 1 and 60),require_collected boolean not null default true,
 resources text not null default E'Candidate requirements\nAdults aged 18 or older, reliable internet, clear written English, discretion and reliable attendance.\n\nSelection and training\nApplication → interview → training → assessment → company hiring decision. Only the company handles agency relationships.\n\nStrong referrals\nExplain the role accurately. Get the candidate’s permission before sharing contact details. Recommend reliable people.\n\nRewards\nA hire bonus requires completed training, a passed assessment and an active hire. Retention counts approved days actually worked, not calendar days. Monthly commissions use positive worker contribution and are reviewed after the period closes.\n\nFAQ\nSubmitting a candidate does not guarantee hiring or a reward. Duplicate applications do not create additional attribution. Ask an administrator to review an incorrect attribution. Payment follows review and applicable cash collection.\n\nAccount safety\nNever submit agency passwords or banking credentials in this portal.',updated_at timestamptz not null default now()
);
insert into public.evzon_referral_config(id) values(true);
create table public.evzon_referrals (
 id uuid primary key default gen_random_uuid(),referrer_id uuid not null references public.evzon_profiles(id),candidate_name text not null check(length(candidate_name) between 1 and 120),worker_id text unique,source text not null default 'Referral link',
 stage text not null default 'Submitted' check(stage in ('Submitted','Under Review','Interview','Training','Training Completed','Hired','Active','30-Day Milestone Completed','Rejected','Withdrawn')),
 training_complete boolean not null default false,assessment_passed boolean not null default false,hired_on date,worker_status text not null default '',active_days int not null default 0,terms jsonb not null,reason text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index evzon_referrals_referrer_idx on public.evzon_referrals(referrer_id,created_at);
create table evzon_private.contacts(referral_id uuid primary key references public.evzon_referrals(id) on delete cascade,email text unique,phone text not null default '',notes text not null default '');
create table public.evzon_rewards (
 id uuid primary key default gen_random_uuid(),referral_id uuid not null references public.evzon_referrals(id),referrer_id uuid not null references public.evzon_profiles(id),worker_id text not null,
 kind text not null check(kind in ('Hire','Retention','Commission')),period date not null,amount numeric not null default 0 check(amount>=0),
 status text not null default 'Not yet eligible' check(status in ('Not yet eligible','Pending review','Approved','Payable','Paid','Rejected','Cancelled')),
 explanation text not null,terms jsonb not null,earned_at timestamptz,approved_at timestamptz,approved_by uuid references public.evzon_profiles(id),paid_at timestamptz,paid_by uuid references public.evzon_profiles(id),payment_reference text not null default '',reason text not null default '',created_at timestamptz not null default now(),unique(worker_id,kind,period)
);
create unique index evzon_rewards_milestone_unique on public.evzon_rewards(worker_id,kind) where kind in ('Hire','Retention');
create index evzon_rewards_referrer_idx on public.evzon_rewards(referrer_id,period);
create index evzon_rewards_referral_idx on public.evzon_rewards(referral_id);
create index evzon_rewards_status_idx on public.evzon_rewards(status,period);
create table public.evzon_events(id uuid primary key default gen_random_uuid(),referrer_id uuid not null references public.evzon_profiles(id),referral_id uuid references public.evzon_referrals(id),message text not null,created_at timestamptz not null default now());
create index evzon_events_referrer_idx on public.evzon_events(referrer_id,created_at desc);
create index evzon_events_referral_idx on public.evzon_events(referral_id);
create table evzon_private.audit(id uuid primary key default gen_random_uuid(),actor uuid references public.evzon_profiles(id),action text not null,before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
create table evzon_private.periods(worker_id text not null,period date not null,revenue numeric not null check(revenue>=0),compensation numeric not null check(compensation>=0),invoices text[] not null,finalized_by uuid not null references public.evzon_profiles(id),finalized_at timestamptz not null default now(),primary key(worker_id,period));
create table evzon_private.workday_exceptions(worker_id text not null,day date not null check(day<=current_date),reason text not null check(length(reason)>=8),approved_by uuid not null references public.evzon_profiles(id),primary key(worker_id,day));
create table evzon_private.payouts(reward_id uuid primary key references public.evzon_rewards(id),amount numeric not null,reference text not null,paid_by uuid not null references public.evzon_profiles(id),paid_at timestamptz not null default now());
;
