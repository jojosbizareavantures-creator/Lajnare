# EVZON — complete Vercel source

This is the EVZON application exported from its published source and adapted to standard Next.js for Vercel. It contains the frontend, server API routes, financial engine, Supabase database migrations and RLS/functions, chatter-account Edge Function, training images/content, assessment bank, and existing automated checks. The current live website was not changed by this export.

**Use the existing Supabase project `pgoypntgazhwacbuikzl`.** Your users, applications, workers, financial records, training approvals, and results stay there. Moving the web app to Vercel does not require copying or resetting that database.

## Deploy to Vercel

1. Extract this ZIP and upload the contents of the `evzon-vercel` folder to a private Git repository. `package.json`, `app/`, and `vercel.json` must be at the repository root.
2. In Vercel, choose **Add New → Project**, import that repository, and select **Next.js**. Root Directory is the repository root. Use Node.js **22.x**, Install Command **`npm ci`**, Build Command **`npm run build`**, and the default output directory.
3. Copy the variables from `.env.example` into Vercel's **Settings → Environment Variables** before deploying. Add them for Production, and for Preview if you intend to test authenticated preview deployments.
4. Deploy. Then follow [the domain and authentication setup](docs/DOMAIN_LAUNCH.md) to connect your Namecheap domain.

No ChatGPT or Sites runtime is required by this export. Vercel runs the Next.js frontend and API routes; Supabase continues to provide database, authentication, and privileged chatter-account provisioning.

## Required environment variables

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | `https://pgoypntgazhwacbuikzl.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | The publishable key for that existing project, from Supabase Project Settings → API Keys. A legacy anon key is also supported. |
| `APPLICATION_INGEST_SECRET` | The **existing** signing secret from `evzon_private.application_ingest_config`; it must match the database. |
| `NEXT_PUBLIC_SITE_URL` | `https://evzonchatting.com` |
| `NEXT_PUBLIC_GA_MEASUREMENT_ID` | `G-15PY8YRJ87` (already set as the code default) |

To obtain the existing application signing secret, run this read-only query in the **owner's Supabase SQL Editor**, then paste its result directly into the private Vercel environment-variable field:

```sql
select secret from evzon_private.application_ingest_config where id = true;
```

Do not add that value to Git, put it into a `NEXT_PUBLIC_` variable, or generate a different value on just one side. Without the matching secret, the application form intentionally remains unavailable. The ZIP contains no production secrets or user-data dump. SMTP credentials remain configured in Supabase; the Vercel app does not need them or a service-role key.

## Google Analytics

GA4 web stream **`G-15PY8YRJ87`** is configured. Public pages send sanitized pageviews only after the visitor allows optional analytics. Account/admin/chatter pages are excluded, and localhost/preview traffic is not sent. The consent controls work in English and Macedonian. See [ANALYTICS.md](docs/ANALYTICS.md) for property settings and verification after deployment. This export has not yet been deployed, so live data collection is not claimed.

## Run locally

Use Node.js 22.x. Copy `.env.example` to `.env.local`, fill in the same variables, then run:

```sh
npm ci
npm run dev
```

For a production build:

```sh
npm run build
npm start
```

## What is included

| Path | Purpose |
| --- | --- |
| `app/`, `components/`, `hooks/`, `public/` | Public pages, application form, admin panel, referral portal, chatter portal, bilingual interface and visual assets. |
| `app/api/`, `app/auth/` | Server endpoints, session/authentication flows, workspace saves, applications/notifications, referrals, training, exams and private images. |
| `lib/finance.ts`, `components/store.tsx` | Central financial formulas, persistence, autosave and conflict handling. |
| `lib/supabase-server.ts` | Server-side environment configuration and authenticated Supabase access. |
| `proxy.ts`, `lib/response-security.ts` | Production security headers and private-page cache/indexing rules. |
| `supabase/migrations/` | All 23 recorded migrations from the connected database, with the actual applied version identifiers. |
| `supabase/functions/evzon-chatter-accounts/` | Current deployed version of the administrator-validated chatter provisioning function. |
| `supabase/seed.sql` | Current 34-chapter course and 155 assessment questions for an **empty** development/staging project only. It refuses to run if any Auth user already exists. |
| `content/`, `lib/server/training-assets.json` | Current published guide text, translations, source tracking and all 25 protected training images. |
| `tests/`, `scripts/training/`, `scripts/exams/` | Existing checks and course/assessment maintenance tools. |
| `EXPORT_INFO.json` | Source commit, export scope and target platform. |

The unfinished replacement guides/videos discussed later in the conversation were not published and are not represented as completed in this export. This package corresponds to the current published application. Generated build output, dependencies, local credentials and production personal/financial data are intentionally not included; `npm ci` restores the locked dependencies.

## Backend

For the existing project, **do not rerun the baseline SQL, reset the database or reseed it**. Its schema and Edge Function are already deployed. Update the Auth URLs after connecting your domain, and retain existing SMTP settings.

For a separate, empty development/staging Supabase project, [BACKEND.md](supabase/BACKEND.md) describes the included migrations, content seed, first-admin setup and Edge Function. The historical standalone SQL files outside `migrations/` and the `scripts/*/releases/` files document previous releases; they are not an additional sequence to replay after the migrations/seed.

## Verification

```sh
npm test
npm run typecheck
python scripts/training/source_fidelity.py
python scripts/exams/validate-bank.py
```

The standard Next.js production build, TypeScript validation, and all 136 application and analytics checks passed on Node.js 22.23.4. Production-server HTTP checks also passed for 18 routes, including protected API rejection when signed out and the public referral terms response. The original published source remains unchanged. This is a source-code export, not a claim that a Vercel deployment, Namecheap DNS, or new-domain email/login acceptance has already completed.

Reference documentation: [Vercel Next.js](https://vercel.com/docs/frameworks/full-stack/nextjs), [Vercel domains](https://vercel.com/docs/domains/working-with-domains), [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).
