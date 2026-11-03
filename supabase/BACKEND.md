# Supabase backend source

## Existing EVZON project

The deployed backend is `pgoypntgazhwacbuikzl`. Reuse it when moving the website to Vercel. Its accounts, financial data, applications, referrals, attendance, payroll, training progress and exam attempts stay in Supabase. No database reset, new project, migration replay or seed is required for a web-host migration.

The web server needs `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and the matching `APPLICATION_INGEST_SECRET`. The signing secret is intentionally excluded from the ZIP. The account-provisioning function already runs in Supabase and receives its privileged credentials through Supabase's own environment.

## Included source

- `migrations/`: all 23 migrations recorded on the existing project, exported using their real version identifiers. They include the tables, RLS, role checks, transactional workspace/referral/application commands, notifications, training progression and supervised assessment engine.
- `functions/evzon-chatter-accounts/index.ts`: current deployed function version 2. It validates the caller's identity and current approved ADMIN profile before using the Auth admin API. Public registration cannot grant CHATTER or ADMIN access.
- `config.toml`: local CLI configuration and function JWT-gateway behavior. The function's `verify_jwt = false` setting matches production because authentication is explicitly performed inside the function; the caller still needs a valid, authorized session.
- `seed.sql`: the current published course and assessment bank. No real users, workers, applications, salaries, payouts or authentication credentials are included. It is guarded against use on a database with existing Auth users.
- Other `.sql` files and `scripts/*/releases/`: historical source/reference material. Do not execute all SQL files indiscriminately; some describe earlier versions of objects that the migration chain later replaces.

## Separate empty development/staging project

Use this only for a genuinely new, empty project. Install the official Supabase CLI and use its `--help` to confirm commands for your version. For a local environment, Docker is also required.

```sh
supabase login
supabase link --project-ref YOUR_NEW_EMPTY_PROJECT_REF
supabase db push --dry-run
supabase db push --include-seed
supabase functions deploy evzon-chatter-accounts
```

The configuration is for an empty project; do not point these seeding commands at the existing production backend. The seed installs content/answers, not application users. Supabase's local development stack is not a public hosting server.

For a fresh local database:

```sh
supabase start
supabase db reset --local
```

The historical migration chain has the original owner's bootstrap email. Before registering your first admin in a **new** project, explicitly configure the verified address you intend to own that project. In the project's owner SQL Editor:

```sql
begin;
delete from evzon_private.admin_bootstrap;
insert into evzon_private.admin_bootstrap(email)
values(lower('REPLACE_WITH_YOUR_ADMIN_EMAIL'));
commit;
```

Then register that email and complete email verification. Subsequent public registrations remain referral partners. Configure the new project's SMTP, exact Auth URLs and email templates before production email use. New projects need their own application signing secret from `evzon_private.application_ingest_config` placed in the server's private environment.

## Database content and accounts

This ZIP contains source and static training/assessment content; it is not a production database backup. Use Supabase's backup/export facilities for a full data migration. Keep an existing backend to retain existing passwords, verified accounts, saved finances and learner history.

The optional database test files create fixtures inside rolled-back transactions. They are development verification files, not production seed scripts. No database test or bootstrap was executed against production while preparing this export.

Security status at export: exposed EVZON tables have RLS enabled. Private tables intentionally have no direct user-access policies and are reached through authorized commands. The existing Supabase project reports leaked-password protection disabled; enable it in Auth settings if available on your plan. This export did not change the plan or Auth settings.
