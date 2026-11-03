# Google Analytics 4

The Vercel app is configured for web stream **`G-15PY8YRJ87`**. The ID is public configuration, not a password. It is the application default, and `.env.example` contains the same value. `NEXT_PUBLIC_GA_MEASUREMENT_ID` can override it at build time; an explicit empty or invalid value disables analytics.

## When it records visits

- The page must be one of the public landing-page routes or `/apply`.
- The browser must be on `https://evzonchatting.com` or `https://www.evzonchatting.com`, using the configured production origin. Localhost and Vercel preview domains do not send tracking events.
- The visitor must choose **Allow analytics**. The Google script is not loaded before that choice. The preference is remembered in the browser. **Analytics preferences** allows the visitor to change it later.

Advertising storage, ad user data, ad personalization, Google signals and advertising-personalization signals are disabled. Withdrawing consent disables collection and clears the app's GA cookies. Account, admin, referrer, chatter, API, login, registration and password-recovery pages are excluded.

The app's pageview payload contains a fixed public page title, the canonical public pathname and the referring site's origin. It removes query strings/fragments and does not add email addresses, names, application answers, referral codes, tokens, financial records or user IDs to its events. No extra application/submission/conversion events were added.

## Google Analytics property settings

The integration sends explicit `page_view` events and disables the tag's automatic initial pageview. In Google Analytics **Admin → Data streams → your web stream → Enhanced measurement**, turn off **Page changes based on browser history events** to avoid additional automatic history events. For a visitor/pageview-only setup, also turn off automatic form interactions, site-search, outbound-link, download and other enhanced-measurement events you do not intend to collect. These property settings are separate from website source and cannot be changed using a Measurement ID alone.

## Verify after deploying

1. Publish this updated code on Vercel and connect `evzonchatting.com`.
2. Open the production website in a browser without an ad blocker and choose **Allow analytics**.
3. Visit a few public pages. Check the browser Network panel for `gtag/js?id=G-15PY8YRJ87` and Analytics collection requests with the same measurement ID.
4. Open the property's **Reports → Realtime** report. Use Tag Assistant/DebugView when investigating missing events.
5. Decline analytics in a fresh browser session and verify no Google tag loads. Account pages should not load the tag, regardless of the saved preference.

Build/tests validate the configured ID, production/public-page allowlist, consent gate and sanitized payloads. Live collection cannot be confirmed until the updated application is deployed and a real permitted visit reaches the property. Counts reflect measurable, consenting visitors; ad blockers and declined consent can reduce reported totals.

No Google account access, property changes, production deployment or fabricated Analytics events were used while preparing the code.

References: [Google pageview measurement](https://developers.google.com/analytics/devguides/collection/ga4/views), [Consent mode](https://developers.google.com/tag-platform/security/guides/consent), [Google privacy controls](https://developers.google.com/tag-platform/security/guides/privacy).
