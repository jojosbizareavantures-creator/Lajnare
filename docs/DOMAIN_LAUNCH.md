# evzonchatting.com — Namecheap + Vercel

Deploy the project on Vercel first. Keep using the existing Supabase backend. The existing ChatGPT-hosted website is a separate deployment and is not altered by this export.

## 1. Add the domains in Vercel

In **Vercel → your project → Settings → Domains**, add:

- `evzonchatting.com`
- `www.evzonchatting.com`

Choose `evzonchatting.com` as the production domain and redirect `www` to it. Copy the **exact DNS records shown by your Vercel project**. They can be project-specific; this package does not hardcode or guess their IP addresses or CNAME targets.

## 2. Set the DNS records in Namecheap

If the domain uses Namecheap BasicDNS/PremiumDNS, open **Namecheap → Domain List → Manage → Advanced DNS → Host Records**.

| Record | Host | Value |
| --- | --- | --- |
| A | `@` | Exact apex target shown by Vercel. |
| CNAME | `www` | Exact CNAME target shown by Vercel. |
| TXT, if requested | Exact verification host from Vercel | Exact verification value from Vercel. |

Set TTL to Automatic/default. Replace conflicting parking or previous website-routing records for `@` and `www`, including URL Redirect records that conflict with the chosen setup. Keep mail/MX, SPF, DKIM, DMARC and unrelated TXT records. If the domain uses other nameservers, edit DNS at that nameserver provider instead.

The old `custom-domains.chatgpt.site` CNAME and the `162.159.143.30` / `172.66.3.26` A records belong to the earlier hosting arrangement. **Do not use them for the Vercel deployment.** Replace old website-routing entries with Vercel's entries. Old verification TXT records do not route traffic; do not remove unrelated email records.

Wait until Vercel shows a valid configuration and HTTPS works on both hostnames. Namecheap registers the domain; Vercel hosts the web application. No separate Namecheap web-hosting package is required for this setup.

## 3. Configure Supabase authentication

In [the existing project's URL Configuration](https://supabase.com/dashboard/project/pgoypntgazhwacbuikzl/auth/url-configuration), set **Site URL** to:

```text
https://evzonchatting.com
```

Allow these exact **Redirect URLs**, retaining the old website's entries while migrating:

```text
https://evzonchatting.com/auth/confirm
https://evzonchatting.com/auth/confirm?recovery=1
https://www.evzonchatting.com/auth/confirm
https://www.evzonchatting.com/auth/confirm?recovery=1
```

If testing email flows on the Vercel deployment URL before attaching the domain, also allow that exact deployment's `/auth/confirm` and `/auth/confirm?recovery=1` URLs. Do not use a broad production wildcard for arbitrary `.vercel.app` sites.

Keep email confirmation enabled. Existing verification/recovery templates must point to `/auth/confirm` using `token_hash` and `type=email` or `type=recovery`. Keep the current SMTP configuration. No SMTP password or Supabase service-role key belongs in Vercel's browser variables.

Users sign in again on the new domain because cookies are domain-scoped. Existing accounts, referral codes, applications and workforce records remain in the same Supabase project.

## 4. Verify the launch

Check the landing pages, language selector, application form and referral attribution; then verify admin, partner and chatter sign-in, sign-out, a fresh verification email, and a fresh password-reset email. Confirm protected API calls cannot be used when signed out. Check admin/chatter links through normal clicks and make sure financial edits persist.

Vercel Deployment Protection, if enabled for production, must match the intended public launch. The app's own Supabase roles and API authorization remain required regardless of Vercel's hosting-access setting.

References: [Vercel domain configuration](https://vercel.com/docs/domains/working-with-domains), [Namecheap host records](https://www.namecheap.com/support/knowledgebase/article.aspx/319/2237/how-can-i-set-up-an-a-address-record-for-my-domain/), [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).
