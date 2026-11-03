# EVZON chatter portal

The private entry point is `/chatterportal`. It is absent from public navigation and the sitemap. Accounts use the separate `CHATTER` role and are created by an approved administrator through the admin panel. Public registration creates a referral-partner account, not a chatter account.

## Administrator workflow

1. Add the worker under Workers, choose Training status, and set their compensation.
2. Open Chatter management → Accounts → Create chatter account. Select the worker, enter their name, email, temporary password (at least 12 characters), and training start date. Share the private portal link and password privately. Initial sign-in requires a different password.
3. Learning Materials 1–4 contain the published course. The learner marks chapters studied and submits each material for trainer review. Approval of the previous material unlocks the next material immediately once training has started; materials do not require waiting another calendar day.
4. Stage 5 is Practicing for exams. All five practice tests must be completed; a passing practice score is not required. Completing them does not unlock the final exam automatically.
5. In the exam administration area, explicitly authorize the eligible learner's final exam. One authorization permits one attempt. The final has 30 shuffled questions, is supervised by the CEO over Discord screen sharing, and is graded on the server. A failed attempt offers feedback and further learning; another attempt requires a fresh authorization.
6. A passing final records the hiring milestone. Guided shadowing and the CEO trial shift still require their scheduled dates and explicit completion approvals. The final approval activates the linked worker and hides training for that chatter.
7. Assign shifts in Schedule & attendance. The chatter sees their own shifts in Europe/Skopje time and can clock in and out.
8. Review actual attendance before it enters approved-hour payroll. An administrator can close a forgotten timer with a reason. Review payouts, pay externally, then record the Paid status and payment reference. The portal records payments; it does not transfer money.

## Data protection

The account Edge Function verifies the session token and current approved ADMIN role before calling the Supabase Auth admin API. Chatter accounts can access only their own records and permitted announcements. The app does not accept client-controlled role claims. Temporary plaintext passwords are not retained in application records or audit logs.

Training reads, material approvals, exam authorizations, question/option order, answer autosaves and submitted results are stored in Supabase. Historical exam snapshots preserve the questions the learner actually saw. Current source content includes 34 chapters, 25 images and 155 questions across five practice tests and the final.

The later guide-replacement request was not completed or published before this export. The ZIP contains the source and content matching the currently published application, without claiming the uploaded replacement videos are integrated.
