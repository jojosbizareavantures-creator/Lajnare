-- Private curriculum and study progress. Exposed functions validate the current profile on every call.
create table evzon_private.training_units(
 id text primary key check(id ~ '^[a-z0-9-]{1,80}$'),
 day int not null references public.evzon_chatter_lessons(day),
 section text not null check(length(section) between 1 and 160),
 title text not null check(length(title) between 1 and 200),title_mk text not null default '' check(length(title_mk)<=200),
 summary text not null default '' check(length(summary)<=1000),
 body text not null check(length(body) between 1 and 40000),body_mk text not null default '' check(length(body_mk)<=40000),
 note text not null default '' check(length(note)<=2000),assets jsonb not null default '[]' check(jsonb_typeof(assets)='array'),
 position int not null,minutes int not null check(minutes between 1 and 240),published boolean not null default false,
 revision int not null default 1 check(revision>0),source text not null default '',updated_at timestamptz not null default now()
);
create index training_units_day_position on evzon_private.training_units(day,position);
create table evzon_private.training_reads(
 chatter_id uuid not null references public.evzon_chatter_accounts(id) on delete cascade,
 unit_id text not null references evzon_private.training_units(id) on delete cascade,
 revision int not null,read_at timestamptz not null default now(),notes text not null default '' check(length(notes)<=2000),
 primary key(chatter_id,unit_id)
);
create index training_reads_unit on evzon_private.training_reads(unit_id);
alter table evzon_private.training_units enable row level security;
alter table evzon_private.training_reads enable row level security;
revoke all on evzon_private.training_units,evzon_private.training_reads from public,anon,authenticated;

create function evzon_private.training_day_access(p_day int) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
 evzon_private.is_admin() or (
 evzon_private.is_chatter() and exists(
 select 1 from public.evzon_chatter_accounts a join public.evzon_chatter_lessons l on l.day=p_day
 where a.id=auth.uid() and a.completed_at is null and not a.must_change_password and l.published
 and (now() at time zone 'Europe/Skopje')::date>=a.training_start+p_day-1
 and (select count(*) from public.evzon_chatter_progress p where p.chatter_id=a.id and p.day<p_day and p.status='Approved')=p_day-1
 )))
$$;

create function evzon_private.training_portal() returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin();a public.evzon_chatter_accounts;begin
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 select * into a from public.evzon_chatter_accounts where id=auth.uid();
 if not admin and (a.id is null or a.must_change_password) then raise exception 'EVZON_FORBIDDEN';end if;
 return jsonb_build_object(
 'units',(select coalesce(jsonb_agg((to_jsonb(u)-'body'-'body_mk'-'assets'-'note')||jsonb_build_object(
 'unlocked',evzon_private.training_day_access(u.day),
 'body',case when evzon_private.training_day_access(u.day) then u.body else '' end,
 'body_mk',case when evzon_private.training_day_access(u.day) then u.body_mk else '' end,
 'note',case when evzon_private.training_day_access(u.day) then u.note else '' end,
 'assets',case when evzon_private.training_day_access(u.day) then u.assets else '[]'::jsonb end
 ) order by u.position),'[]') from evzon_private.training_units u join public.evzon_chatter_lessons l on l.day=u.day
 where admin or (u.published and l.published and a.completed_at is null)),
 'reads',(select coalesce(jsonb_agg(to_jsonb(r) order by r.read_at),'[]') from evzon_private.training_reads r where admin or (r.chatter_id=auth.uid() and a.completed_at is null))
 );
end $$;

create function evzon_private.training_command(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=evzon_private.is_admin();u evzon_private.training_units;begin
 if auth.uid() is null or (not admin and not evzon_private.is_chatter()) then raise exception 'EVZON_FORBIDDEN';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>150000 then raise exception 'EVZON_INVALID: Invalid training request';end if;
 perform pg_advisory_xact_lock(782541);
 select * into u from evzon_private.training_units where id=p_data->>'id' for update;
 if u.id is null then raise exception 'EVZON_INVALID: Chapter not found';end if;
 if p_action='read' then
  if admin or not u.published or not evzon_private.training_day_access(u.day) then raise exception 'EVZON_FORBIDDEN';end if;
  if (p_data->>'revision')::int is distinct from u.revision then raise exception 'EVZON_INVALID: This chapter changed. Refresh and review it again';end if;
  if length(coalesce(p_data->>'notes',''))>2000 then raise exception 'EVZON_INVALID: Keep your note under 2,000 characters';end if;
  insert into evzon_private.training_reads(chatter_id,unit_id,revision,notes) values(auth.uid(),u.id,u.revision,trim(coalesce(p_data->>'notes','')))
   on conflict(chatter_id,unit_id) do update set revision=excluded.revision,notes=excluded.notes,read_at=now();
 elsif p_action='edit-unit' and admin then
  if (p_data->>'revision')::int is distinct from u.revision then raise exception 'EVZON_INVALID: Another administrator changed this chapter. Refresh before saving';end if;
  if length(trim(coalesce(p_data->>'title',''))) not between 1 and 200 or length(trim(coalesce(p_data->>'body',''))) not between 1 and 40000 then raise exception 'EVZON_INVALID: A chapter needs a title and 1–40,000 characters of content';end if;
  update evzon_private.training_units set title=trim(p_data->>'title'),title_mk=coalesce(p_data->>'title_mk',''),body=trim(p_data->>'body'),body_mk=coalesce(p_data->>'body_mk',''),note=coalesce(p_data->>'note',''),summary=coalesce(p_data->>'summary',''),published=coalesce((p_data->>'published')::boolean,false),revision=revision+1,updated_at=now() where id=u.id;
  perform evzon_private.audit('Training chapter updated',to_jsonb(u),p_data||jsonb_build_object('revision',u.revision+1));
 else raise exception 'EVZON_FORBIDDEN';end if;
 return evzon_private.training_portal();
end $$;

create function evzon_private.training_asset(p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from evzon_private.training_units u
 where (u.published or evzon_private.is_admin()) and evzon_private.training_day_access(u.day)
 and exists(select 1 from jsonb_array_elements(u.assets) x where x->>'name'=p_name));
$$;

-- The same guard applies to API calls, direct RPC calls, submissions and trainer approvals.
create function evzon_private.require_training_reads() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.day<=4 and new.status in ('Submitted','Approved') then
  if not exists(select 1 from evzon_private.training_units where day=new.day and published) then raise exception 'EVZON_INVALID: Your trainer has not published the chapters for this day';end if;
  if exists(select 1 from evzon_private.training_units u where u.day=new.day and u.published and not exists(
   select 1 from evzon_private.training_reads r where r.chatter_id=new.chatter_id and r.unit_id=u.id and r.revision=u.revision
  )) then raise exception 'EVZON_INVALID: Study and mark every chapter complete before this day can be reviewed';end if;
 end if;
 return new;
end $$;
create trigger require_training_reads before insert or update on public.evzon_chatter_progress for each row execute function evzon_private.require_training_reads();

create function public.evzon_training_portal() returns jsonb language sql security invoker set search_path='' as $$select evzon_private.training_portal();$$;
create function public.evzon_training_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select evzon_private.training_command(p_action,p_data);$$;
create function public.evzon_training_asset(p_name text) returns boolean language sql security invoker set search_path='' as $$select evzon_private.training_asset(p_name);$$;
revoke all on function evzon_private.training_day_access(int),evzon_private.training_portal(),evzon_private.training_command(text,jsonb),evzon_private.training_asset(text),evzon_private.require_training_reads(),public.evzon_training_portal(),public.evzon_training_command(text,jsonb),public.evzon_training_asset(text) from public,anon,authenticated;
grant execute on function evzon_private.training_portal(),evzon_private.training_command(text,jsonb),evzon_private.training_asset(text),public.evzon_training_portal(),public.evzon_training_command(text,jsonb),public.evzon_training_asset(text) to authenticated;

-- Latest supplied text only: Pasted text(4).txt. All 15 original images are served by an authenticated server route.
insert into evzon_private.training_units(id,day,section,title,title_mk,summary,body,body_mk,note,assets,position,minutes,published,revision,source)
select id,day,section,title,title_mk,summary,body,body_mk,note,assets,position,minutes,published,revision,source from jsonb_to_recordset($evzon_course$[
  {
    "id": "foundations",
    "day": 1,
    "section": "Foundations",
    "title": "The role and the shift routine",
    "title_mk": "",
    "body": "## The role\nYou communicate on an authorized creator account, using its approved voice and information. Read the history, remember relevant details, respond thoughtfully and present authorized paid content when appropriate. Good work combines conversation, organization and accurate offers. Revenue is an outcome, not a guarantee.\n\n## Common beginner mistakes\n- Pitching too early\n- Pitching too often\n- Writing too much\n- Begging after a no\n- Discounting the price\nSending an exhaustive description before interest is established; a paid offer still needs a truthful description.\n- Not taking notes\n- Waiting for the fan to lead\n- Ending chats flat\nLosing track of other conversations while one person is not interested in a purchase.\n\n## Shift routine\n- Character bible refresh\n- Message every new subscriber\n- Clear every unread\n- Work spenders top-down\n- 1–2 mass messages\nReview outstanding questions before logging off; respect refusals and the 24-hour failed-pitch rule.\n- Write notes\n- Hand mid-deal chats to the next shift",
    "body_mk": "",
    "summary": "Understand your responsibilities before opening the inbox.",
    "assets": [],
    "note": "",
    "position": 1,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "workspace",
    "day": 1,
    "section": "Infloww",
    "title": "Workspace, access and the inbox",
    "title_mk": "",
    "body": "## 1. What Infloww is\nInfloww is a desktop CRM (Mac/Windows — there is no mobile app) that replaces the OnlyFans website interface. It's built for agencies, and it supports OnlyFans, Fansly and MYM in one dashboard.\n\nTwo reasons you'll use it:\n\n- Speed — the inbox is built for chatting, so you handle far more conversations per shift than through the OF site\n- Accountability — every message, price and dollar is logged against you in real time\nRead that second point carefully. You are being watched, in the good way. Fast replies, clean pricing and consistent output show up in your favour.\n\n## 2. Getting set up\nYour manager will create a seat for you with role-based permissions. Expect:\n\n- A login you don't share with anyone\n- no ability to download content (the Vault is permission-controlled so your laptop can't leak her content)\n- One dashboard that may hold several creator profiles — always check which account you're typing into before sending\nFirst thing on setup: build your workspace. Infloww lets you split an inbox into up to 9 groups. Do this on day one:\n\n- Group 1: new subscribers\n- Group 2: spenders / whales\n- Group 3: mid-tier\n- Group 4: non-spenders to work\n- Group 5: parked / follow up later\n- Group 6: sexting sessions in progress\nNow you work one group at a time instead of drowning.\n\n## 3. The inbox\n- Conversations are unified across accounts you have access to\n- Filter the inbox to hide groups you're not working right now\n- Pin the messages that matter — his favourite outfit, his job, his kid's name — right in the chat window so it's visible while you type\n- Auto-unsend exists so back-to-back sends don't look spammy. Use it when sending multiple messages quickly",
    "body_mk": "",
    "summary": "Account selection, your own login and a clear inbox.",
    "assets": [],
    "note": "This source describes a particular Infloww workspace. Features, integrations and permissions may differ in your assigned account. Your trainer will demonstrate the current interface. Never share logins or export creator content.",
    "position": 2,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "insights-notes",
    "day": 1,
    "section": "Infloww",
    "title": "Fan insights and useful notes",
    "title_mk": "",
    "body": "## 4. Fan insights — read this before every first message\nClick into any fan and you get their purchase history, subscription status and highest-ever purchase.\n\nUse it:\n\n- Highest purchase $5 → send cheap PPVs first, warm him up\n- Highest purchase $100+ → go straight to premium, don't insult him with a $5 item\n- Never spoken before → open with rapport, no pitch\n- Expiring soon → reactivation script\nThis one habit separates chatters who hit their numbers from chatters who don't.\n\n## 5. Notes and the fan snapshot\nEvery fan has a note field. Use it. Non-negotiable.\n\nWhat goes in a note:\n\n- Name, age, country, job\n- Kinks, preferences, limits\n- Favourite outfit / set\n- What he bought and when\n- A declined offer or stated preference that must be respected\n- Your hook for next time\nNotes support continuity between authorized team members. Record only information needed for the work; never collect passwords, payment details or unnecessary sensitive personal information.",
    "body_mk": "",
    "summary": "Read previous purchases and preferences; keep accurate handover notes.",
    "assets": [],
    "note": "Spending history is context, not permission to pressure someone or override the approved price list.",
    "position": 3,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "tools-library",
    "day": 1,
    "section": "Infloww",
    "title": "Scripts, content library and lists",
    "title_mk": "",
    "body": "## 6. Scripts\nInfloww Scripts let you save templates for common scenarios — and they can hold text, video snippets and PPVs, not just words.\n\nHow to use them properly:\n\nDon't fire them verbatim. Use them as skeletons and personalise the first line.\n- Build a script for each of your ten most common situations\n- Update them monthly with what's actually converting\n## 7. Vault Pro\nContent lives here, bulk-uploaded, tagged and described. There's a smart search, so you can find content while mid-conversation without leaving the chat.\n\nHow to use it well:\n\n- Know the tag structure so you can find things in two seconds\n- Use search when a fan asks for something specific\n- You may not be able to download — that's normal, don't panic\n## 8. Smart Lists and segments\nSmart Lists auto-group fans by spending habits and engagement using include/exclude filters. They update themselves as fan behaviour changes.\n\nPractical use: build a list of everyone who spent over $50 in the last 30 days. That's your priority queue. Work it before anything else.",
    "body_mk": "",
    "summary": "Find approved material and organize the conversations you manage.",
    "assets": [],
    "note": "",
    "position": 4,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "infloww-shift",
    "day": 1,
    "section": "Infloww",
    "title": "Messaging tools and shift etiquette",
    "title_mk": "",
    "body": "## 9. Mass messages and Smart Messages\n- Mass messages can land in fans' Priority inbox rather than the \"All\" tab — a real reach advantage\n- Scheduling spreads a send across hours instead of blasting everyone at once\nPriority mass message sequences fire automated follow-ups, and they break the sequence automatically once a fan replies so a human can step in. On by default — don't turn it off\n- Smart Messages trigger on fan actions (like expiring soon) and are usually where automated discount codes live\nYour job with all of these: send, then stay online. The replies are the revenue.\n\n## 10. Your stats\nInfloww logs everything in real time: messages sent, PPVs priced, revenue per shift, per chatter. Managers see it same-day.\n\nThis is why consistent approved pricing matters. If you discount, it's visible. If you undersell a whale a $5 item, it's visible. If you go quiet for 40 minutes, it's visible.\n\nWhat to watch yourself:\n\n- Reply speed\n- PPV unlock rate on personalised sends\n- Number of fans spoken to\n## 11. Tool etiquette\n- Never leave a fan on read — the log shows it\n- Log out cleanly, don't leave drafts\n- Never take a fan off-platform (no WhatsApp, no Instagram)\n- Hand over mid-deal conversations properly, with a note",
    "body_mk": "",
    "summary": "Prepare sends, monitor replies and hand over ongoing conversations.",
    "assets": [],
    "note": "Use only the automations and permissions configured by your manager. A source claim about a default setting is not an instruction to enable it.",
    "position": 5,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "working-rules",
    "day": 1,
    "section": "Foundations",
    "title": "How to use these guides consistently",
    "title_mk": "",
    "body": "## One working reference\nThese chapters organize the supplied guides. Examples are reference material; creator instructions, approved prices and platform rules govern live work.\n\n## Resolve the differences in the source\n- A teaser can be brief. Before payment, accurately explain what the customer receives and the price. Do not mislabel an existing item as custom or exclusive.\n- The sales guide and daily SOP use a 24-hour window for new subscribers and failed pitches. Do not turn a screenshot's immediate-follow-up suggestion into repeated sales pressure. Answer genuine questions; stop when someone declines.\n- Three conversational messages after a purchase are a minimum in the source example, not automatic permission to pitch again. Pacing ranges are guidelines, not quotas.\n- Free previews or loyalty extras need prior authorization. An example suggesting a free item does not override the creator's policy.\n- Screenshot prices and paid badges are historical examples. They are not current prices, promised results, wages or entries in EVZON's financial records.\n\n## Clear boundaries\nUse the approved creator voice without inventing personal experiences, private relationships, live activity or meetings. Answer questions about who is responding accurately, following the account's disclosure policy. If unsure, pause and ask the EVZON trainer or administrator.\n\nA refusal or spending limit ends the sales attempt. Complaints deserve a factual review, not guilt or emotional pressure. Keep communication on the approved platform.\n\n## Your learning record\nRead each chapter and its references, then mark it studied. You may add a question for your trainer. This records your study progress; the trainer separately reviews and approves the day. Days 5–6 are shadowing and Day 7 is the supervised Discord trial.",
    "body_mk": "",
    "summary": "The rules that take priority when examples differ.",
    "assets": [],
    "note": "",
    "position": 6,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "flow-intro",
    "day": 2,
    "section": "Conversation paths",
    "title": "Purpose and pacing",
    "title_mk": "",
    "body": "# CUSTOMER CHAT AND PAY-PER-VIEW (PPV) SOP\n## Complete Workflow and Training Notes\n\n**Source:** Customer Chat and Pay Per View SOP —  Made by Stefan\n \n**Format:** Interactive 20-step conversation flowchart\n\n---\n\n# 1. PURPOSE OF THE WORKFLOW\n\nThis SOP explains how to handle a customer conversation from the opening message through potential sexual conversation, teasing, a pay-per-view (PPV) offer, the customer's response, and the follow-up.\n\nThe workflow has two primary routes:\n\n1. **Main sales route:** Start a normal conversation, gradually transition to a sexual conversation when appropriate, build anticipation, present a PPV, and respond according to the outcome.\n2. **No-pitch route:** If the customer does not want the conversation to become sexual, keep the interaction normal and focus on relationship building.\n\nThe main principle is to respond to the customer's interest and reactions rather than forcing the conversation through a predetermined sales sequence.\n\n# 2. MESSAGE-PACING SYSTEM\n\nThe flowchart uses three pacing categories. These define the approximate number of messages for each stage.\n\n## SLOW — 10+ messages\n\nUse this pacing for:\n- Starting the conversation.\n- Gradually transitioning the tone.\n- Returning the conversation to normal after an unsuccessful PPV.\n- Aftercare and maintaining the relationship.\n- Continuing a normal, non-sexual conversation.\n\n## MEDIUM — 5 to 10 messages\n\nUse this pacing for:\n- Sexual conversations.\n- Persuasion following an initial PPV that the customer did not unlock but remains interested in.\n- Introducing another PPV after a successful purchase.\n\n## FAST — 1 to 5 messages\n\nUse this pacing for:\n- Teasing before the PPV.\n- Presenting the PPV.\n- Returning to sexual conversation after a successful purchase while the customer remains interested.\n\n**Important:** These are the ranges displayed in the flowchart. They are guidelines for pacing, not a requirement to send unnecessary messages or ignore the customer's responses.\n\n---",
    "body_mk": "",
    "summary": "Understand the two routes and the slow, medium and fast pacing ranges.",
    "assets": [],
    "note": "",
    "position": 7,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "flow-opening",
    "day": 2,
    "section": "Conversation paths",
    "title": "Steps 1–5 · Opening through the offer",
    "title_mk": "",
    "body": "# 3. STEP-BY-STEP WORKFLOW\n\n## STEP 1 — START OF THE CONVERSATION\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Instructions\n\nEvery chat begins here. Some conversations never need to become sexual.\n\nStart naturally, as a normal person would. Establish a conversation before attempting to sell anything.\n\n### Required approach\n\n- Open like a normal person.\n- Talk about the customer's name, their day, and where they are.\n- Do not start selling immediately.\n- Take your time and build rapport.\n- Understand that ten messages or more at this stage is normal.\n\n### Main objective\n\nEstablish a comfortable conversation and earn the opportunity to introduce a sales offer later.\n\n### Available routes\n\n**Route A — Continue toward the main sales flow:** Proceed to Step 2, changing a normal conversation to a sexual one, when appropriate.\n\n**Route B — No pitch:** Proceed to Step 17 when the conversation should remain non-sexual.\n\n---\n\n## STEP 2 — CHANGING A NORMAL CONVERSATION TO SEXUAL\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Instructions\n\nThe objective is to turn a normal conversation into a sexual one slowly.\n\n### Required approach\n\n1. Test the water with light flirting.\n2. Read how the customer responds.\n3. Step it up a little at a time.\n4. Never jump too quickly.\n5. If the customer pulls back, take the no-pitch path instead.\n\n### Decision point\n\n**Is the customer open to making the conversation sexual?**\n\n- **Yes — Open to it:** Continue to Step 3, Sexual Conversations.\n- **No — Not open to it:** Proceed to Step 18, They Don't Want It Sexual, Keep It Normal.\n\n### Main objective\n\nDetermine whether the customer is comfortable with the change in tone before progressing.\n\nDo not assume that a customer is interested simply because they continue replying.\n\n---\n\n## STEP 3 — SEXUAL CONVERSATIONS\n\n**Pacing:** MEDIUM  \n**Message target:** 5 to 10 messages\n\n### Instructions\n\nThe customer is open to the conversation becoming sexual.\n\n### Required approach\n\n- Match their energy.\n- Build on what they say they like.\n- Allow the conversation to develop naturally.\n- Use five to ten messages.\n- Keep the conversation long enough to build momentum, but short enough to avoid losing it.\n\n### Main objective\n\nBuild on the customer's demonstrated interest and prepare for the teasing stage.\n\n### Next step\n\nProceed to Step 4, Teasing.\n\n---\n\n## STEP 4 — TEASING\n\n**Pacing:** FAST  \n**Message target:** 1 to 5 messages\n\n### Instructions\n\nHint at what you have without giving it away.\n\n### Required approach\n\n- Keep it quick.\n- Use one to five messages.\n- Create anticipation for the content being offered.\n- Set up the PPV pitch.\n- Do not allow the moment to cool off unnecessarily.\n\n### Main objective\n\nCreate a natural transition from the sexual conversation to the PPV offer.\n\n### Next step\n\nProceed to Step 5, PPV.\n\n---\n\n## STEP 5 — PPV\n\n**Pacing:** FAST  \n**Message target:** 1 to 5 messages\n\n### Instructions\n\nThe PPV drop must communicate three things:\n\n1. What the content is.\n2. Why the customer would want it.\n3. The price, presented together with the content offer.\n\n### Required approach\n\n- Say what it is.\n- Explain why they would want it.\n- Send the price and the content offer together.\n- Keep the pitch within one to five messages.\n- Once the offer is sent, observe the customer's response.\n\n### Main objective\n\nPresent a clear offer at the appropriate moment in the conversation.\n\n### Important decision\n\nThe customer's response after the PPV determines which stage comes next.\n\nThere are three possible outcomes:\n\n- **Stage 1:** The customer unlocked the PPV and likes it.\n- **Stage 2:** The customer did not unlock the PPV but is still excited.\n- **Stage 3:** The customer did not unlock the PPV or did not like it.\n\nDo not handle all three outcomes identically.\n\n---",
    "body_mk": "",
    "summary": "Follow the customer’s interest and make the offer clear.",
    "assets": [],
    "note": "",
    "position": 8,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 4
  },
  {
    "id": "flow-purchase",
    "day": 2,
    "section": "Conversation paths",
    "title": "Steps 6–9 · A successful purchase",
    "title_mk": "",
    "body": "# 4. THE THREE POST-PPV OUTCOMES\n\n## STEP 6 — STAGE 1: UNLOCKED THE PPV AND LIKES IT\n\n**Category:** Successful purchase\n\nThe customer unlocked the PPV and likes the content.\n\n### Interpretation\n\nThis is the best outcome in the workflow.\n\nThe customer's positive response creates an opportunity to continue the conversation and potentially introduce another PPV.\n\n### Required approach\n\n- Keep the energy going.\n- Continue the conversation instead of ending it immediately.\n- Prepare for the next interaction while the customer remains engaged.\n\n### Next step\n\nProceed to Step 7, Sexual Conversation and Tease Again.\n\n---\n\n## STEP 7 — SEXUAL CONVERSATION AND TEASE AGAIN\n\n**Pacing:** FAST  \n**Message target:** 1 to 5 messages\n\n### Instructions\n\nThe customer unlocked and liked the previous PPV, so return directly to sexual conversation and teasing.\n\n### Required approach\n\n1. React to the customer's response first.\n2. Continue the sexual conversation.\n3. Build on the customer's reaction to the previous content.\n4. Move quickly while the customer is still excited.\n5. Keep this stage to one to five messages.\n\n### Main objective\n\nMaintain the customer's interest and create a natural opening for another PPV.\n\n### Next step\n\nProceed to Step 8, Another PPV.\n\n---\n\n## STEP 8 — ANOTHER PPV\n\n**Pacing:** MEDIUM  \n**Message target:** 5 to 10 messages\n\nThe flowchart labels this node as **Another PPV**, with medium pacing.\n\n### Workflow interpretation\n\nAfter a successful purchase and the subsequent sexual conversation, the workflow allows another PPV offer to be introduced.\n\nThe next decision is whether the customer unlocks the next PPV and continues to like it.\n\n### Next step\n\nProceed to Step 9, Do They Unlock It and Still Like It?\n\n*The node's detailed explanatory text is not fully displayed in the recording, so additional rules beyond its label and pacing cannot be confirmed.*\n\n---\n\n## STEP 9 — DO THEY UNLOCK IT AND STILL LIKE IT?\n\n**Decision point:** Yes or No\n\n### Instructions\n\nThe flowchart describes this as a loop check.\n\n### If YES\n\nThe customer unlocks the PPV and still likes it.\n\n- Remain in Stage 1.\n- Return to Step 7, Sexual Conversation and Tease Again.\n- Continue the loop while the customer remains interested.\n\n### If NO\n\nThe customer does not unlock the PPV or does not continue to like it.\n\n- Leave the Stage 1 loop.\n- Move to Stage 3.\n- Proceed to Step 14, De-escalate the Conversation.\n\n### Main objective\n\nDetermine whether the successful-purchase route should continue or whether the conversation needs to move away from the sales sequence.\n\n**Key distinction:** A previous successful purchase does not guarantee that the customer will want every subsequent offer.\n\n---",
    "body_mk": "",
    "summary": "Respond to the purchase and check whether interest continues.",
    "assets": [],
    "note": "",
    "position": 9,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "flow-no-unlock",
    "day": 2,
    "section": "Conversation paths",
    "title": "Steps 10–13 · No unlock or a negative response",
    "title_mk": "",
    "body": "## STEP 10 — STAGE 2: DIDN'T UNLOCK, STILL EXCITED\n\n**Category:** Unsuccessful initial unlock, but interest remains\n\nThe customer did not unlock the PPV but is still sexually engaged or excited.\n\n### Interpretation\n\nThe flowchart treats this differently from a customer who has lost interest.\n\nThe sale may still be possible, but the customer has not purchased the content yet.\n\n### Required approach\n\nContinue to Step 11, Persuasion to Unlock the PPV.\n\n*The Stage 2 heading and its transition to the persuasion step are visible in the recording. The detailed instructions are provided in Step 11.*\n\n---\n\n## STEP 11 — PERSUASION TO UNLOCK THE PPV\n\n**Pacing:** MEDIUM  \n**Message target:** 5 to 10 messages\n\n### Instructions\n\nThe customer did not unlock the PPV but remains excited.\n\nThe stated objective is to work toward the unlock while the customer's interest remains.\n\n### Required approach\n\n- Explain the content again.\n- Help the customer understand what is being offered.\n- Do not beg.\n- Use five to ten messages.\n- Accept the customer's answer after this stage.\n\n### Main objective\n\nClarify the value of the content and give the customer an opportunity to make a decision.\n\n### Important boundary\n\nThe instruction is to persuade, not to beg or continue indefinitely. If the customer clearly declines, accept the answer.\n\n### Next step\n\nProceed to Step 12, Do They Unlock the PPV?\n\n---\n\n## STEP 12 — DO THEY UNLOCK THE PPV?\n\n**Decision point:** Yes or No\n\n### If YES\n\nThe customer unlocks the PPV.\n\n- Move into the Stage 1 loop.\n- Proceed to Step 7, Sexual Conversation and Tease Again.\n\n### If NO\n\nThe customer still does not unlock the PPV.\n\n- Move to Stage 3.\n- Proceed to Step 14, De-escalate the Conversation.\n\n### Main objective\n\nDetermine whether the persuasion stage resulted in a purchase.\n\nDo not treat continued excitement as equivalent to a completed purchase. The actual unlock determines the route.\n\n---\n\n## STEP 13 — STAGE 3: DIDN'T UNLOCK OR DIDN'T LIKE IT\n\n**Category:** Unsuccessful purchase outcome or negative content response\n\nStage 3 applies when the customer either:\n\n- Did not unlock the PPV; or\n- Did not like the content.\n\n### Interpretation\n\nThis route is different from Stage 2.\n\nStage 2 means the customer did not unlock but remains excited. Stage 3 means the PPV did not result in the desired outcome, so the conversation should move away from the sales sequence.\n\n### Next step\n\nProceed to Step 14, De-escalate the Conversation.\n\n---",
    "body_mk": "",
    "summary": "Distinguish a question from a refusal; choose the right next step.",
    "assets": [],
    "note": "The pacing range is not a requirement to send 5–10 follow-ups. Clarify only when the customer wants clarification, accept the answer, and apply the failed-pitch timing rule.",
    "position": 10,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "flow-no-pitch",
    "day": 2,
    "section": "Conversation paths",
    "title": "Steps 14–20 · De-escalation and the no-pitch route",
    "title_mk": "",
    "body": "## STEP 14 — DE-ESCALATE THE CONVERSATION\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Instructions\n\nThe customer did not unlock the PPV or did not like it.\n\nThe goal is to bring the conversation back down.\n\n### Required approach\n\n- Lower the temperature of the conversation.\n- Move back toward normal chat.\n- Slow down again.\n- Continue for ten messages or more.\n\n### Main objective\n\nTransition away from the unsuccessful sales interaction without making the customer uncomfortable or damaging the relationship.\n\n### Next step\n\nProceed to Step 15, Aftercare.\n\n---\n\n## STEP 15 — AFTERCARE\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Instructions\n\nAftercare is about emotional connection, not sexual conversation.\n\n### Required approach\n\n- Focus on the personal connection.\n- Do not apply pressure.\n- Never abruptly close the conversation.\n- Make sure the customer can leave the interaction feeling good about the chat.\n- Do not use guilt or sulking.\n\n### Main objective\n\nPreserve the relationship regardless of whether the customer purchased the content.\n\n### Core rule\n\nThe customer should feel comfortable continuing to interact in the future, whether they bought the PPV or not.\n\n### Next step\n\nProceed to Step 16, End or Continue Non-Sexual Conversation.\n\n---\n\n## STEP 16 — END OR CONTINUE NON-SEXUAL CONVERSATION\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Instructions\n\nWrap up warmly or continue chatting as normal.\n\n### Required approach\n\n- End the conversation warmly if appropriate.\n- Alternatively, carry on with normal conversation.\n- Leave the door open for future interactions.\n- Do not treat a refusal to purchase today as a permanent rejection.\n\nThe flowchart summarizes this with the principle:\n\n\"Today's no is often next week's yes.\"\n\n### Main objective\n\nFinish the interaction in a positive way and preserve the opportunity for future conversations.\n\n---\n\n# 5. THE NO-PITCH ROUTE\n\nThe main flowchart contains an alternative route for customers who do not want the conversation to become sexual.\n\nThis route is separate from the post-PPV stages.\n\n## STEP 17 — NO PITCH\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Position in the workflow\n\nThis is an alternative to progressing through the sexual-conversation and PPV sequence.\n\n### Workflow interpretation\n\nIf the conversation should remain non-sexual, do not force a pitch. Continue through the normal-conversation route.\n\nThe opening step explicitly states that some chats never need to turn sexual at all.\n\n*The detailed explanatory panel for this node is not opened in the recording; the node title and pacing are visible.*\n\n### Next step\n\nProceed to Step 18, They Don't Want It Sexual, Keep It Normal, when the customer is not open to sexual conversation.\n\n---\n\n## STEP 18 — THEY DON'T WANT IT SEXUAL, KEEP IT NORMAL\n\n**Pacing:** SLOW  \n**Message target:** 10+ messages\n\n### Position in the workflow\n\nThis branch follows the customer's lack of interest in making the conversation sexual.\n\n### Required approach\n\nThe main instruction from Step 2 is explicit: if the customer pulls back, take the no-pitch path instead.\n\nTherefore:\n\n- Do not continue escalating the conversation.\n- Keep the interaction normal.\n- Respect the customer's response.\n- Continue through the relationship-building route.\n\n### Next step\n\nProceed to Step 19, Relationship Building.\n\n*The node's separate detailed instruction panel is not displayed in the recording.*\n\n---\n\n## STEP 19 — RELATIONSHIP BUILDING\n\n**Pacing:** SLOW\n\n### Position in the workflow\n\nRelationship Building follows the node indicating that the customer does not want the conversation to become sexual.\n\n### Workflow interpretation\n\nThis branch maintains a normal conversational relationship rather than attempting to force the customer back into the sexual-conversation sequence.\n\n### Next step\n\nProceed to Step 20, Continue Normal Conversation (No Pitch).\n\n*The recording shows the node and its connection to the next step, but does not expose a detailed instruction panel for this node.*\n\n---\n\n## STEP 20 — CONTINUE NORMAL CONVERSATION (NO PITCH)\n\n**Pacing:** SLOW\n\n### Position in the workflow\n\nThis is the continuation of the no-pitch route.\n\n### Workflow interpretation\n\nContinue the normal conversation without introducing the PPV sales sequence.\n\nThe objective is to preserve the interaction as a normal conversation when that is the appropriate route.\n\n*No separate detailed instruction panel for this node is displayed in the recording.*\n\n---",
    "body_mk": "",
    "summary": "Return to normal conversation and respect the customer’s preference.",
    "assets": [],
    "note": "",
    "position": 11,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 4
  },
  {
    "id": "flow-reference",
    "day": 2,
    "section": "Conversation paths",
    "title": "Decision tree and quick reference",
    "title_mk": "",
    "body": "# 6. COMPLETE DECISION TREE\n\n## Starting the conversation\n\nSTART OF THE CONVERSATION\n- Normal opening.\n- Slow pacing.\n- 10+ messages.\n\nThen choose the appropriate route.\n\n### Route A — Customer is open to sexual conversation\n\n1. Change normal conversation to sexual.\n2. Confirm the customer's interest through their response.\n3. Move into sexual conversations.\n4. Build on the customer's interests.\n5. Tease the upcoming content.\n6. Present the PPV.\n7. Evaluate the result.\n\n### Route B — Customer is not open to sexual conversation\n\n1. Do not force the transition.\n2. Take the no-pitch route.\n3. Keep the conversation normal.\n4. Focus on relationship building.\n5. Continue normal conversation without a pitch.\n\n## After the PPV\n\n### Outcome A — Unlocked and liked it\n\nPPV → Stage 1 → Sexual conversation and tease again → Another PPV → Check the response.\n\n- If the next PPV is unlocked and the customer still likes it, continue the Stage 1 loop.\n- If not, move to Stage 3.\n\n### Outcome B — Didn't unlock, still excited\n\nPPV → Stage 2 → Persuasion to unlock the PPV → Decision.\n\n- If unlocked, move to the Stage 1 loop.\n- If not unlocked, move to Stage 3.\n\n### Outcome C — Didn't unlock or didn't like it\n\nPPV → Stage 3 → De-escalate the conversation → Aftercare → End or continue non-sexual conversation.\n\nThe purpose of this route is to return to normal conversation and maintain the relationship rather than continue pushing the offer.\n\n---\n\n# 7. QUICK-REFERENCE TABLE\n\n| Step | Stage | Pacing | Message target |\n|---|---|---|---|\n| 1 | Start of the conversation | Slow | 10+ |\n| 2 | Changing normal conversation to sexual | Slow | 10+ |\n| 3 | Sexual conversations | Medium | 5–10 |\n| 4 | Teasing | Fast | 1–5 |\n| 5 | PPV | Fast | 1–5 |\n| 6 | Stage 1: Unlocked and likes it | Outcome | — |\n| 7 | Sexual conversation and tease again | Fast | 1–5 |\n| 8 | Another PPV | Medium | 5–10 |\n| 9 | Do they unlock it and still like it? | Decision | — |\n| 10 | Stage 2: Didn't unlock, still excited | Outcome | — |\n| 11 | Persuasion to unlock the PPV | Medium | 5–10 |\n| 12 | Do they unlock the PPV? | Decision | — |\n| 13 | Stage 3: Didn't unlock or didn't like it | Outcome | — |\n| 14 | De-escalate the conversation | Slow | 10+ |\n| 15 | Aftercare | Slow | 10+ |\n| 16 | End or continue non-sexual conversation | Slow | 10+ |\n| 17 | No pitch | Slow | 10+ |\n| 18 | They don't want it sexual, keep it normal | Slow | 10+ |\n| 19 | Relationship building | Slow | Not specified separately |\n| 20 | Continue normal conversation (no pitch) | Slow | Not specified separately |\n\n**Pacing legend**\n- Slow = 10+ messages\n- Medium = 5–10 messages\n- Fast = 1–5 messages\n\nThe outcome and decision nodes do not have their own independent message targets.\n\n---\n\n# 8. KEY OPERATING RULES\n\n1. **Start naturally.** Do not begin by immediately selling content.\n2. **Build rapport first.** The opening stage is intended to establish a real conversation.\n3. **Transition gradually.** Test the customer's response before changing the conversation's tone.\n4. **Match the customer's energy.** Build on what the customer actually says and responds to.\n5. **Keep teasing brief.** The flowchart allocates one to five messages for teasing.\n6. **Make the PPV offer clear.** Explain the content, why it is appealing, and its price together.\n7. **Classify the outcome correctly.** An unlock with positive feedback, no unlock with continued excitement, and a negative response lead to different paths.\n8. **Do not beg.** The persuasion stage explicitly says not to beg.\n9. **Accept the customer's answer.** After the persuasion stage, the workflow moves on rather than continuing indefinitely.\n10. **De-escalate when needed.** An unsuccessful offer should lead back toward normal conversation.\n11. **Use aftercare.** Maintain a positive personal connection whether or not the customer purchases.\n12. **Keep the no-pitch route available.** Not every conversation needs to become sexual or lead to a sale.\n13. **Preserve the relationship.** A customer who does not buy now may still want to interact in the future.\n\n---\n\n# 9. WHAT THE RECORDING DOES AND DOES NOT ESTABLISH\n\n## Explicitly shown in the recording\n\n- A 20-step interactive flowchart.\n- Three pacing levels and their message ranges.\n- The main conversation-to-PPV route.\n- The alternative no-pitch route.\n- Three post-PPV outcome stages.\n- Decision branches based on unlocking the content and liking it.\n- Instructions for teasing, presenting a PPV, persuasion, de-escalation, aftercare, and normal conversation.\n\n## Not fully specified in the visible workflow\n\nThe recording does not expose detailed instruction panels for every node. In particular, the individual instructions for No Pitch, They Don't Want It Sexual, Relationship Building, and Continue Normal Conversation (No Pitch) are not fully shown.\n\nThe recording also does not provide a complete library of verbatim chat messages, specific PPV prices, customer segmentation rules, or platform-specific operating procedures.\n\nThose details should not be invented or treated as official rules without additional source material.\n\n---\n\n# 10. FINAL SUMMARY\n\nThe complete workflow is built around three principles:\n\n**First: Build the conversation before presenting an offer.** Start naturally, develop rapport, and only change the conversation's tone when the customer is open to it.\n\n**Second: Let the customer's response determine the next step.** After the PPV, distinguish between a successful purchase, an interested customer who has not purchased, and a customer who is no longer interested or did not like the content.\n\n**Third: Preserve the relationship regardless of the outcome.** When a sale does not happen, stop pushing, return to normal conversation, and maintain a positive interaction.\n\nThe intended result is a structured conversation process in which each stage has a defined objective, a recommended pace, and a clear next step.\n\n**End of SOP.**",
    "body_mk": "",
    "summary": "Explore the paths and review all 20 stages.",
    "assets": [],
    "note": "",
    "position": 12,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 6
  },
  {
    "id": "no-pitch-practice",
    "day": 2,
    "section": "Customer care",
    "title": "When someone does not want to buy",
    "title_mk": "",
    "body": "Conversation Flow 2.\n# WHAT TO DO WHEN A CUSTOMER WON’T BUY\n## Chatter Training SOP — Step-by-Step Guide\n\n### 1. PURPOSE OF THIS SOP\n\nNot every conversation will lead to a sale. Some subscribers are not ready to buy, some prefer normal conversation, and others do not want sexual conversation at all.\n\nThe goal is to recognize which situation you are dealing with and respond appropriately instead of pushing for a sale that the subscriber has already declined.\n\n**Core principle:** Build the relationship first. A conversation does not have to result in a purchase to be valuable.\n\n---\n\n## 2. THE THREE MAIN RULES\n\n### Rule 1: Do not force a sale\n\nIf the subscriber is not interested in purchasing, do not repeatedly send offers or turn every message into a sales pitch.\n\n- Pay attention to their responses.\n- Respect a clear refusal.\n- Do not make them feel guilty for not buying.\n- Avoid repeating the same offer when they have already declined.\n- Keep the conversation natural.\n\n### Rule 2: Follow the subscriber’s preferred conversation style\n\nNot every subscriber wants the conversation to become sexual. If they want to keep things normal, follow their lead.\n\n- Continue discussing topics they enjoy.\n- Ask questions and show genuine interest.\n- Avoid introducing sexual topics after they have indicated that they are uncomfortable with them.\n- Do not treat a subscriber’s lack of interest in sexual conversation as a problem that must be fixed.\n\n### Rule 3: Build the relationship over time\n\nSome subscribers will return to purchase later, while others may continue to enjoy conversations without buying.\n\n- Remember details they voluntarily share.\n- Refer back to previous conversations when appropriate.\n- Be consistent and attentive.\n- Give the subscriber a reason to enjoy returning to the conversation.\n- Do not assume that every interaction must end with a purchase.\n\n---\n\n## 3. STEP-BY-STEP WORKFLOW\n\n### STEP 1 — Start the conversation normally\n\n**Pace: SLOW — 10+ messages**\n\nEvery chat starts here. Sometimes it never needs to turn sexual.\n\nStart by having a normal conversation and getting a sense of the subscriber’s mood and interests.\n\n**What to do:**\n1. Open with a natural greeting.\n2. Ask how their day is going.\n3. Respond to what they actually say instead of sending generic questions repeatedly.\n4. Share a little personality and keep the interaction conversational.\n5. Pay attention to whether they seem interested in continuing.\n\n**Example:**\n\nSubscriber: “Hey, how are you doing?”\n\nChatter: “I’m doing pretty well, just having a relaxed evening. How’s your day been?”\n\nSubscriber: “Pretty boring, honestly.”\n\nChatter: “One of those days? What have you been up to?”\n\n**Important:** Do not assume that every subscriber needs to be moved toward sexual conversation or a paid offer.\n\n### STEP 2 — Check whether they are interested in sexual conversation\n\nOnly move toward sexual conversation when the subscriber’s responses indicate that they are interested and comfortable with it.\n\n**What to do:**\n- Notice their tone and the topics they introduce.\n- Look for clear, reciprocal interest rather than interpreting every friendly message as sexual interest.\n- If they do not engage with the direction of the conversation, do not force it.\n- If they say they are not interested, respect that and return to normal conversation.\n\n**Example — subscriber is not interested:**\n\nChatter: “How has your evening been?”\n\nSubscriber: “Good, just relaxing and watching a show.”\n\nChatter: “Nice, what are you watching?”\n\nContinue naturally. There is no need to turn the conversation sexual.\n\n### STEP 3 — Choose the correct path\n\nOnce you understand the subscriber’s interest, choose the appropriate route.\n\nThere are two main paths:\n\n**Path A: No pitch**\n\nUse this when the conversation is not going toward a sale, the subscriber is not interested in purchasing, or the situation calls for relationship-building instead.\n\n**Path B: They do not want to make it sexual**\n\nUse this when the subscriber has indicated that they want to keep the conversation nonsexual.\n\nThese paths are not failures. They are appropriate ways to continue the interaction without damaging the relationship.\n\n---\n\n## 4. PATH A — NO PITCH\n\n**Pace: SLOW — 10+ messages**\n\nSome conversations are never going to be a sale today. They still matter.\n\nThis path runs slower, and the goal is the relationship, not the unlock.\n\n### What to do\n\n1. Stop pushing the current offer.\n2. Acknowledge the subscriber’s response without arguing.\n3. Return to a normal topic.\n4. Keep the conversation engaging without bringing up another purchase immediately.\n5. Continue building rapport naturally.\n\n**Example:**\n\nChatter: “I have something you might enjoy seeing.”\n\nSubscriber: “Not today, I’m just here to talk.”\n\nChatter: “That’s completely fine. What have you been up to today?”\n\nSubscriber: “Work mostly. It’s been a long week.”\n\nChatter: “Sounds exhausting. Was it one of those weeks where everything happened at once?”\n\nThe conversation continues without pressure or another immediate sales attempt.\n\n### What NOT to do\n\nAvoid responses such as:\n\n- “Come on, just buy it.”\n- “You never buy anything.”\n- “If you liked me, you would unlock it.”\n- Sending repeated offers after the subscriber has said no.\n- Making the subscriber feel that conversation is conditional on spending money.\n\nThese approaches can undermine trust and make the interaction feel transactional.\n\n---\n\n## 5. PATH B — THEY DON’T WANT TO MAKE IT SEXUAL\n\n**Pace: SLOW — 10+ messages**\n\nIf the subscriber does not want sexual conversation, keep the conversation normal.\n\n### Step 1: Respect their preference\n\nDo not argue with them, tease them about it, or continue introducing sexual topics.\n\n**Example:**\n\nSubscriber: “I’m not really in the mood for that. I just want to chat.”\n\nChatter: “No problem. We can just talk. How has your week been?”\n\n### Step 2: Build the relationship\n\nKeep the conversation focused on the subscriber and the topics they enjoy.\n\nThe workflow emphasizes:\n- Remembering details and bringing them back up.\n- Showing interest in what the subscriber tells you.\n- Keeping the conversation natural.\n- Maintaining a friendly and consistent tone.\n\n**Example:**\n\nSubscriber: “I finally got the weekend off.”\n\nChatter: “That must feel good after a busy week. Have you got anything planned, or are you just going to relax?”\n\nSubscriber: “Probably relax and play some games.”\n\nChatter: “Honestly, that sounds like a good weekend. What have you been playing lately?”\n\nThe focus is on creating a good conversation, not trying to redirect it toward a sale.\n\n### Step 3: Continue normal conversation\n\nOnce rapport has been established, keep chatting normally.\n\nThere is no need to force the subscriber back into sexual conversation or introduce a paid offer simply because the conversation has continued for several messages.\n\n**Key principle:** If they want a normal conversation, give them a normal conversation.\n\n---",
    "body_mk": "",
    "summary": "Recognize the no-pitch route and follow the customer’s lead.",
    "assets": [],
    "note": "",
    "position": 13,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 6
  },
  {
    "id": "rapport-practice",
    "day": 2,
    "section": "Customer care",
    "title": "Listening, follow-ups and the final checklist",
    "title_mk": "",
    "body": "## 6. RELATIONSHIP-BUILDING TECHNIQUES\n\nThe video specifically emphasizes remembering details and bringing them back up.\n\n### A. Remember relevant details\n\nIf a subscriber tells you about work, a hobby, a trip, or something they are looking forward to, use that information naturally in a later conversation.\n\n**Example:**\n\nPrevious conversation: “I have a big presentation on Friday.”\n\nLater conversation: “Hey, how did that presentation go? You mentioned you were preparing for it.”\n\nThis demonstrates that you paid attention.\n\n### B. Ask follow-up questions\n\nInstead of changing topics immediately, show interest in the answer.\n\n**Weak response:**\n\nSubscriber: “I had a really stressful day.”\n\nChatter: “Oh okay. What are you doing tonight?”\n\n**Better response:**\n\nSubscriber: “I had a really stressful day.”\n\nChatter: “Sorry to hear that. Was it work that made it stressful, or just one of those days where everything goes wrong?”\n\n### C. Keep the tone natural\n\nAvoid making every message sound like a sales script. Use the context of the conversation to decide what to say next.\n\n### D. Do not make promises you cannot keep\n\nBuild trust through consistency and honest communication. Do not pretend to have personal experiences or make commitments on behalf of the creator that you cannot fulfill.\n\n---\n\n## 7. CONTINUE NORMAL CONVERSATION — NO PITCH\n\n**Pace: SLOW — 10+ messages**\n\nThe final step of this route is simple: carry on as normal, with no pitch.\n\nThe video’s guidance is to keep showing up. There is no deadline on this path.\n\n### Practical approach\n\n- Respond to what the subscriber says.\n- Ask relevant questions.\n- Keep track of useful conversational context.\n- Let the interaction develop at its own pace.\n- Do not introduce a sale just to fill a silence.\n- Accept that some conversations may remain noncommercial.\n\n**Example conversation:**\n\nSubscriber: “I’ve been trying to get back into the gym.”\n\nChatter: “Nice, how long has it been since you last went regularly?”\n\nSubscriber: “Probably about six months.”\n\nChatter: “That’s a decent break. Are you starting slowly again or jumping straight back into your old routine?”\n\nSubscriber: “Trying to take it slowly.”\n\nChatter: “Probably the smarter way to do it. It’s easier to stay consistent when you don’t overdo it straight away.”\n\nThis conversation provides value through engagement rather than an immediate sale.\n\n---\n\n## 8. QUICK DECISION GUIDE\n\n| Subscriber’s situation | Correct response |\n|---|---|\n| They are chatting normally | Continue normal conversation |\n| They do not want to buy today | Use the no-pitch path |\n| They decline a paid offer | Accept the answer and move on |\n| They do not want sexual conversation | Keep the conversation nonsexual |\n| They share personal interests or experiences | Ask relevant follow-up questions |\n| They return after a previous conversation | Refer back to relevant details naturally |\n| They remain uninterested in buying | Continue without pressure or accept that the conversation may end |\n\n---\n\n## 9. COMMON MISTAKES TO AVOID\n\n**Mistake 1: Treating every chat as a sales opportunity**\n\nNot every conversation should become a pitch. The relationship can be valuable even when there is no immediate purchase.\n\n**Mistake 2: Ignoring a refusal**\n\nOnce a subscriber has clearly declined, repeatedly pushing the same offer can damage trust.\n\n**Mistake 3: Making sexual conversation the default**\n\nDo not assume that a subscriber wants sexual conversation simply because they are messaging a creator.\n\n**Mistake 4: Forgetting what the subscriber says**\n\nRepeatedly asking for information they have already shared can make the conversation feel impersonal.\n\n**Mistake 5: Being overly scripted**\n\nA checklist should guide your decisions, not dictate every message. Adapt your replies to the actual conversation.\n\n**Mistake 6: Judging success only by immediate revenue**\n\nA subscriber who does not buy today should not automatically be treated as a failed conversation. However, relationship-building should remain genuine and should not become a pretext for pressuring someone later.\n\n---\n\n## 10. FINAL CHECKLIST FOR CHATTERS\n\nBefore replying, ask yourself:\n\n- [ ] Am I responding to what the subscriber actually said?\n- [ ] Have they shown that they are comfortable with the direction of the conversation?\n- [ ] Have they declined an offer or said they do not want sexual conversation?\n- [ ] Should I stop pitching and return to normal conversation?\n- [ ] Can I ask a relevant follow-up question?\n- [ ] Am I remembering useful details without making the interaction feel forced?\n- [ ] Am I respecting the subscriber’s boundaries?\n\n### THE MAIN TAKEAWAY\n\n**When a subscriber does not want to buy, do not force the sale. When they do not want sexual conversation, keep it normal. Build rapport, remember details, and let the conversation develop naturally.**\n\nA good chatter knows when to sell—and when not to sell.",
    "body_mk": "",
    "summary": "Review the supplied examples of thoughtful, ordinary conversation.",
    "assets": [],
    "note": "",
    "position": 14,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 4
  },
  {
    "id": "pitch-method",
    "day": 3,
    "section": "PPV offers",
    "title": "The warm-up, the offer and the response",
    "title_mk": "",
    "body": "3. How to Sales pitch:\n(Every situation is different, so use what you studied accordingly.)\n\n1. Warm-Up\nThe warm-up is the conversation before the sale.\n\nStructure:\n\nNormal conversation → Tease → Build anticipation → PPV\n\nStart with normal, natural conversation.\nBuild a connection and keep them engaged.\nGradually tease the content/situation.\nOnce they're interested and warmed up, send the PPV.\n\nWhy?\nThe customer should feel engaged and interested before you try to sell them something.\n\n2. PPV — The Sale\nThe PPV itself should be short, clear and persuasive.\n\nStructure:\n\n1. What is it?\nTell them what the content contains.\n\n2. Why do they want it?\nAdd a little persuasion/curiosity.\n\n3. Price + Content\nGive them a good price for the content.\n\nExample:\n\n\"I just took this in the shower 👀 You’re going to love this one… $20\"\n\nSimple formula:\n\nWHAT IT IS → PERSUASION → PRICE + CONTENT\n\nThe training specifically stresses explaining what is in the content and then giving the customer a reason to want to open it.\n\n3. second pitches\n✅ If They Buy\n\nIf they buy then repeat the above until the customer stops spending or is disliking the experience.\nKeep them warm for the next sale.\n\nGive them attention.\nMake them feel good about their purchase.\nContinue the conversation.\n\nBUY → WARM-UP → NEXT PPV\n\n❌ If They Don't Buy\n\nYou have two options, depending on the customer:\n\n1. Convince them to buy\n\nUse FOMO.\nGive them a reason to want the content.\nTry to overcome their hesitation.\n\nNO → PERSUADE → BUY\n\n2. Aftercare\n\nIf they're a hard no, don't keep pushing.\nLook after the customer and continue the conversation.\nKeep them engaged so they're more likely to spend again soon.\n\nNO → AFTERCARE → KEEP THEM WARM → FUTURE PPV -> make sure the customer is very happy and is not upset about spending the money",
    "body_mk": "",
    "summary": "Connect the offer to the conversation and accept the decision.",
    "assets": [],
    "note": "Use genuine relevance rather than fabricated scarcity. Only the creator-approved price list determines the amount you quote.",
    "position": 15,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "pitch-timing",
    "day": 3,
    "section": "PPV offers",
    "title": "Timing, interest and the offer structure",
    "title_mk": "",
    "body": "# MASTERING SALES PITCHES\n## Complete Chatter Training Guide\n\n### 1. Understanding Sales Pitches\n\nThe goal of a sales pitch is to turn a normal conversation into a potential purchase without making the customer feel like every message is an attempt to sell something.\n\nBefore trying to sell content, you need to understand the customer, establish a connection, and identify whether they are interested.\n\nA successful pitch should fit naturally into the conversation. You should not suddenly send paid content while discussing something completely unrelated.\n\nTiming is extremely important. Even a good sales pitch can fail if it is sent at the wrong moment.\n\n### 2. The 24-Hour Rules\n\n**Rule 1: No sales pitches within the first 24 hours of a new subscription.**\n\nWhen someone subscribes, they probably do not know much about the model yet.\n\nThey may not know her personality, what content she creates, or what they can expect from interacting with her.\n\nWhy would someone immediately spend additional money on a person they barely know?\n\nSpend this time getting familiar with the subscriber and building the conversation.\n\n**Rule 2: Do not repeat failed sales pitches within 24 hours.**\n\nIf an existing customer has received an offer and decided not to purchase it, do not immediately attempt another sale.\n\nGive the customer some space. Continue the conversation normally instead of repeatedly sending paid offers.\n\nThe important lesson is that constantly pushing someone to buy can reduce their interest in continuing the conversation.\n\n### 3. Building the Conversation Before Selling\n\nA sales conversation should begin naturally.\n\nTalk about normal, everyday subjects such as:\n\n- Their job and what they do for work.\n- Their family and personal life.\n- How their day is going.\n- Their interests and hobbies.\n- What they enjoy talking about.\n\nThese conversations help create familiarity.\n\nThe training explains the transition as:\n\n**Normal life → More provocative conversation → Sales opportunity.**\n\nThe conversation can begin with something ordinary and gradually move toward flirting when the customer shows interest.\n\nFor example, the creator might introduce a topic about getting ready to take a shower, changing clothes, or trying on a new outfit.\n\nThe purpose is to create a natural connection between the conversation and the content being offered.\n\nYou should not make the transition feel random or disconnected.\n\n### 4. Recognizing When Someone Is Ready to Buy\n\nBefore introducing paid content, pay attention to the direction of the conversation.\n\nA customer showing interest in the creator's appearance, asking to see more content, or responding positively to flirting may be more receptive to an offer.\n\nThe objective is to recognize interest rather than force an offer into every conversation.\n\nThe conversation should already have a reason to move toward the type of content you are presenting.\n\nA customer being friendly does not automatically mean they want to purchase something, so pay attention to their responses.\n\n### 5. Using Free Teaser Images\n\nBefore introducing paid content, the training recommends using free teaser images.\n\nThese may include non-explicit photos featuring underwear, bikinis, or similar clothing.\n\nThe free teaser acts as an introduction to the content.\n\nIts purpose is to:\n\n- Capture the customer's attention.\n- Show the type of content available.\n- Create curiosity about additional material.\n- Provide context for a possible paid offer.\n\nAfter sending the teaser, continue the conversation.\n\nDo not immediately abandon the interaction and send a payment request.\n\nThe training specifically emphasizes continuing the flirting and keeping the conversation active.\n\nThe teaser should lead naturally into the next message.\n\n### 6. How to Construct a Sales Pitch\n\nThe training divides a sales pitch into **two essential components**.\n\n**Part 1: What the image is**\n\nThe first part should describe the content.\n\nThe customer should understand what kind of image or video is being offered.\n\nRather than sending paid content without context, explain what they can expect to see.\n\nThis description should relate to the existing conversation.\n\n**Part 2: Why the customer should buy the image**\n\nThe second part explains the appeal of the content.\n\nThe training uses suggestive language, imagination, and questions to make the offer more engaging.\n\nInstead of treating the content as an ordinary product listing, the pitch presents it as something connected to the conversation.\n\n**The complete structure is:**\n\nContent description + Reason to be interested + Conversational question.\n\nBoth parts should work together.\n\nA description without any appeal may feel uninteresting, while a message that creates anticipation without explaining the product can leave the customer unsure what they are purchasing.",
    "body_mk": "",
    "summary": "Study the 24-hour rules and the structure of a clear offer.",
    "assets": [
      {
        "name": "ppv7.png",
        "title": "Transitioning into the PPV",
        "caption": "Reference slide about small talk, reciprocal interest and the transition to an offer."
      },
      {
        "name": "ppv8.png",
        "title": "General transition strategies",
        "caption": "Reference slide about reading responses and matching the offer to expectations. Exclusivity claims must be true."
      }
    ],
    "note": "",
    "position": 16,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 6
  },
  {
    "id": "pitch-examples",
    "day": 3,
    "section": "PPV offers",
    "title": "Price examples and personalized captions",
    "title_mk": "",
    "body": "### 7. First Sales Pitch — $10–$20\n\nThe first sales pitch should use a relatively low price.\n\n**Recommended example price: $10–$20.**\n\nThe training uses a revealing photograph as its first example.\n\nThe objective is to create a simple first purchasing opportunity rather than immediately presenting the most expensive content.\n\nThe pitch begins by describing the image and then adds a suggestive question or comment that relates to it.\n\nFor example, a creator could describe an outfit coming off and ask the customer what they think of the photograph.\n\nThe important principle is that both the content and the caption should belong to the same situation.\n\nThe first sale introduces the customer to purchasing additional content.\n\nIt also gives the chatter information about the customer's willingness to purchase at that particular price.\n\n### 8. Second Sales Pitch — $20–$50\n\nThe second sales pitch introduces a potentially more expensive offer.\n\n**Recommended example price: $20–$50.**\n\nThe training uses a bathroom-themed photograph involving a towel as the example.\n\nThe pitch again follows the same two-part formula.\n\nFirst, describe what is shown in the content.\n\nSecond, create an appealing scenario or question that relates to it.\n\nThe trainer introduces another important concept at this stage:\n\n**FOMO — Fear of Missing Out.**\n\nFOMO refers to the feeling that someone might miss an interesting opportunity by deciding not to participate.\n\nIn sales writing, the intention is to make the offer feel worth considering now rather than something the customer will simply forget.\n\nHowever, the opportunity should be presented accurately rather than using fabricated scarcity or false deadlines.\n\nThe second pitch demonstrates that the same basic writing formula can be used for different images, situations, and price levels.\n\n### 9. Third Sales Pitch — $20–$100\n\nThe third sales pitch introduces a higher-value content example.\n\n**Recommended example price: $20–$100.**\n\nThis stage uses more explicit content than the earlier examples.\n\nThe structure remains unchanged:\n\n**First:** Explain what the image or video contains.\n\n**Second:** Explain why the customer might find it interesting.\n\n**Third:** Connect the message to the conversation rather than treating it as an unrelated advertisement.\n\nThe training demonstrates how the description and emotional appeal can become more direct as the content changes.\n\nThere is no requirement that every customer must go through all three price levels. The amounts represent the examples used in the training.\n\n### 10. Understanding the Progression of Sales\n\nThe overall approach involves starting with a comparatively accessible offer and potentially introducing higher-priced content afterward.\n\nThe video provides these price levels:\n\n| Sales stage | Price range |\n|---|---|\n| First sale | $10–$20 |\n| Second sale | $20–$50 |\n| Third sale | $20–$100 |\n\nThe key idea is to establish purchase interest before assuming the customer will consider a more expensive offer.\n\nEvery additional offer should make sense in the conversation and clearly describe what is being sold.\n\nThe training also refers to a situation where purchases stop after the fifth sale, but it does not provide a complete written fourth- and fifth-pitch framework.",
    "body_mk": "",
    "summary": "Compare the supplied examples without treating their prices as policy.",
    "assets": [
      {
        "name": "ppv1.png",
        "title": "Sending the PPV",
        "caption": "Personalization and selecting relevant content before sending an offer."
      },
      {
        "name": "ppv2.png",
        "title": "Questions before writing a PPV",
        "caption": "A source checklist distinguishing interest in content from interest in the overall interaction."
      },
      {
        "name": "ppv3.png",
        "title": "Caption examples · set one",
        "caption": "Two supplied message screenshots with historical paid badges. These are examples, not a rate card."
      },
      {
        "name": "ppv4.png",
        "title": "Caption examples · set two",
        "caption": "Three supplied message screenshots showing variations in captions and historical paid amounts."
      }
    ],
    "note": "The $10–$20, $20–$50 and $20–$100 ranges belong to the source examples. Use current approved prices. The screenshots are adult reference material supplied for this course; do not send them or copy claims without checking the actual offer.",
    "position": 17,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 7
  },
  {
    "id": "aftercare",
    "day": 3,
    "section": "PPV offers",
    "title": "Aftercare and the complete sales process",
    "title_mk": "",
    "body": "### 11. What to Do When the Customer Stops Buying\n\nA customer may purchase several pieces of content and eventually decide to stop.\n\nThat does not necessarily mean they have lost all interest in the creator.\n\nThey may have reached their spending limit, finished enjoying the available content, or simply want to continue talking.\n\nThe important instruction is not to treat the end of purchasing as the end of the interaction.\n\nThis leads to one of the most important lessons in the training: aftercare.\n\n### 12. Aftercare — What to Do After a Purchase\n\n**Aftercare means looking after the customer after they spend money.**\n\nThe training emphasizes that a customer should feel good about their decision to purchase.\n\nIf someone spends money and the chatter immediately stops communicating, the customer may feel that their attention was only valued while they were paying.\n\nInstead, continue giving the customer attention after the transaction.\n\nThank them for the purchase, respond to them warmly, and make sure they are satisfied with the content.\n\nThe video uses an affectionate follow-up message that communicates enjoyment and asks the customer whether they enjoyed the interaction too.\n\nThe principle is that buying content should not result in the sudden disappearance of attention.\n\nA useful aftercare message should:\n\n- Acknowledge the purchase.\n- Express appreciation.\n- Continue the conversation naturally.\n- Give the customer an opportunity to respond.\n- Leave the interaction on a positive note.\n\nAftercare is intended to help create a positive experience and make customers comfortable returning in the future.\n\n### 13. Why Aftercare Matters\n\nThe trainer emphasizes:\n\n**No aftercare can feel like punishing someone for buying.**\n\nImagine a customer spending money and then receiving no further attention.\n\nFrom their perspective, the conversation may feel like it existed only to obtain the payment.\n\nThat experience may discourage future purchases.\n\nThe training therefore recommends paying attention to the customer after a sale, rather than moving straight to another offer or disappearing.\n\nThe objective is to maintain the relationship with the customer beyond a single transaction.\n\nWarmth and appreciation should be genuine rather than promises of a personal or romantic relationship that does not exist.\n\n### 14. Putting Everything Together\n\nThe complete sales-pitch approach can be organized into the following process.\n\n**Step 1 — Start with conversation.**\n\nGet to know the customer. Ask questions, discuss their day, and develop a natural interaction.\n\n**Step 2 — Respect the timing rules.**\n\nAvoid sales pitches during the first 24 hours of a new subscription, and do not repeatedly pitch existing customers after an unsuccessful offer within the 24-hour window.\n\n**Step 3 — Recognize interest.**\n\nPay attention to whether the customer is genuinely interested in the creator and their content.\n\n**Step 4 — Introduce a relevant scenario.**\n\nMove naturally from everyday conversation to topics associated with the available content, such as changing outfits or getting ready for a shower.\n\n**Step 5 — Use an appropriate free teaser.**\n\nA free bikini or underwear photograph can introduce the theme and help the customer decide whether they are interested.\n\n**Step 6 — Continue the conversation.**\n\nDo not immediately turn every message into a payment request. Keep the interaction natural.\n\n**Step 7 — Construct the paid-content offer.**\n\nDescribe what the content contains and explain its appeal. Use a question or conversational phrasing that fits the interaction.\n\n**Step 8 — Introduce the first purchase opportunity.**\n\nThe training uses $10–$20 as its example starting range.\n\n**Step 9 — Consider further offers only when appropriate.**\n\nThe later examples demonstrate higher price ranges, but the customer's interest, responses, and boundaries should guide whether another offer is suitable.\n\n**Step 10 — Provide aftercare.**\n\nAfter a purchase, continue communicating. Make sure the customer receives the content, feels appreciated, and has an opportunity to enjoy the interaction without being pressured to spend again.\n\n### 15. Final Lessons\n\nA successful sales pitch is not simply about sending a paid image with a price attached.\n\nIt involves timing, conversation, relevance, product presentation, and customer experience.\n\nThe most important teachings are:\n\n- Do not rush to sell to new subscribers.\n- Do not repeatedly pressure customers who decline an offer.\n- Develop natural conversations before introducing content.\n- Use free teasers to establish interest.\n- Make every paid-content pitch relevant to what is being offered.\n- Include both a description and a reason the content may appeal to the buyer.\n- Recognize that different content can be offered at different price levels.\n- Understand the concept of FOMO without using false claims.\n- Continue providing attention and customer service after purchases.\n- Treat aftercare as an essential part of the overall customer experience.\n\n**The complete principle: Build familiarity → Identify interest → Introduce the content → Present a clear offer → Respect the customer's decision → Provide aftercare.**\n\nThe sale is one part of the conversation, not the entire purpose of every message.",
    "body_mk": "",
    "summary": "Continue good service after the purchase and respect spending limits.",
    "assets": [
      {
        "name": "ppv5.png",
        "title": "Engagement after the PPV",
        "caption": "Source slide about post-offer engagement. The course’s timing and refusal rules take precedence over its immediate-follow-up suggestion."
      },
      {
        "name": "ppv6.png",
        "title": "Long-term fan retention",
        "caption": "Notes, temporary exclusions and continued courtesy when someone stops spending. Free extras require authorization."
      }
    ],
    "note": "",
    "position": 18,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 6
  },
  {
    "id": "support-boundaries",
    "day": 4,
    "section": "Difficult situations",
    "title": "Identity, meetings, complaints and boundaries",
    "title_mk": "",
    "body": "## Handling difficult situations\nPause and contact your EVZON trainer or administrator whenever the right response is unclear. The original source names external trainers; use your EVZON contact instead.\n\n## 1. Questions about AI or who is replying\nGive an accurate answer consistent with the creator's approved disclosure policy. Do not deny team involvement or AI use when that would be false. If you do not know, ask your trainer before answering.\n\n## 2. Requests to meet\nDo not imply that spending money will lead to a meeting or personal relationship. Explain the actual boundary: “Meetings are not part of the service offered here.” Only discuss an arrangement that is explicitly authorized and allowed.\n\n## 3. Dissatisfaction with purchased content\nAcknowledge the issue, check what was promised and what was delivered, and refer it for review. A useful reply is: “Thanks for explaining. What did you expect to receive, and what was missing?” Record the facts. Do not blame the customer or promise an unauthorized replacement.\n\n## 4. Requests for free content\nState the approved offer calmly. Use only authorized free previews; do not give paid items away without permission. “I can show you the available preview. The full item has the listed price.” Do not tie a customer's worth or affection to spending.\n\n## 5. Forbidden or out-of-bounds requests\nDo not agree, negotiate or create workarounds. Decline briefly, follow platform reporting procedures where needed, and contact your trainer. Only discuss an alternative if it is actually permitted and approved.",
    "body_mk": "",
    "summary": "Use accurate responses and resolve concerns professionally.",
    "assets": [],
    "note": "Adapted from the ten source scenarios. Misleading identity or meeting promises and guilt-based responses are not included as live-work scripts.",
    "position": 19,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "support-service",
    "day": 4,
    "section": "Difficult situations",
    "title": "Off-platform requests, prices and payment disputes",
    "title_mk": "",
    "body": "## 6. Requests to move off-platform\nKeep the conversation on the approved platform. The source's firm boundary is: “I only chat here. It keeps everything private and safe for both of us.” Do not exchange private contact details or arrange off-platform payment.\n\n## 7. Discounts and haggling\nCheck the approved price list and any authorized campaign. Do not invent a discount, promise satisfaction as a certainty, or claim an existing item was made exclusively for this customer. Offer a different approved item if appropriate, or accept the decision.\n\n## 8. Slow replies\nAcknowledge the wait and answer the outstanding question. The source suggests: “I try my best to reply as quickly as I can. Thanks for being patient.” Do not promise immediate or exclusive availability you cannot provide. Review queue management with your trainer.\n\n## 9. Cheaper content elsewhere\nExplain the actual offer and its approved price without insulting other creators or arguing. The customer decides whether it suits them. Continue politely even if they decline.\n\n## 10. Refund or chargeback requests\nNotify the EVZON administrator. Record the item, agreed terms, delivery, and the customer's concern in the approved system. Follow the platform's process. Do not promise a refund you cannot authorize, hide evidence, or use guilt to discourage a legitimate complaint.\n\n## Escalation handover\nKeep the handover factual: conversation reference, issue, what was promised, what was delivered, and what needs a decision. Keep unnecessary personal information out of the notes.",
    "body_mk": "",
    "summary": "Maintain clear boundaries, consistent pricing and a useful escalation trail.",
    "assets": [],
    "note": "",
    "position": 20,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "mass-messages",
    "day": 4,
    "section": "Daily operations",
    "title": "Targeted mass messages and the example library",
    "title_mk": "",
    "body": "## 1. Introduction to Standard Operating Procedures\n\nStandard Operating Procedures (SOPs) are the rules and processes that every chatter should follow during their shift.\n\nThe purpose of these procedures is to improve communication, maintain consistent selling standards, build relationships with subscribers, and increase revenue over time.\n\nBeing a successful chatter is not simply about responding to messages or selling as much content as possible.\n\nA chatter must understand how to manage different types of subscribers, recognize sales opportunities, maintain customer information, follow pricing rules, and provide a consistent experience.\n\nThe main areas covered in these procedures are:\n\n- Targeted mass direct messages.\n- Catching and retaining new subscribers.\n- Maintaining appropriate content prices.\n- Offering custom content.\n- VIP treatment.\n- Customer labeling and organization.\n- Re-engaging previous customers.\n- Retaining high-spending subscribers.\n- Handling tips and paid offers.\n- Managing unsuccessful sales pitches.\n- Aftercare.\n- Preparing for and managing shifts.\n\n## 2. Targeted Mass Direct Messages\n\nTargeted mass DMs are messages sent to particular groups of subscribers rather than indiscriminately messaging everyone.\n\nDifferent categories of subscribers require different approaches.\n\nFor example, the training identifies the following audiences:\n\n- Online subscribers.\n- Previous spenders.\n- High-spending subscribers, often called whales.\n- New subscribers who need relationship-building.\n- Subscribers who have stopped replying.\n\n**How to send targeted mass messages**\n\nFirst, identify the group you want to contact.\n\nIn Fanvue, navigate to the messaging area and open the mass-message function.\n\nChoose the audience you want to include. The platform provides options such as online users, subscribers, followers, and other filtered groups.\n\nYou can also exclude particular groups.\n\nThis is important because not every message should go to every subscriber.\n\nFor example, a message intended to restart conversations with inactive customers should not automatically be sent to people who are already engaged in an active conversation.\n\nOnce the intended audience is selected, compose a message that fits that group.\n\n**Mass-message examples introduced in the training**\n\nThe lesson includes playful messages such as:\n\n\"Are you being naughty? I see you're online.\"\n\nIt also explores attention-seeking follow-ups asking why someone is online but not replying.\n\nThe purpose of these messages is to encourage responses and restart conversations.\n\nA mass DM does not necessarily need to contain a paid offer. It can simply introduce a question or a conversational opening.\n\n**Main principle:** Use mass messages to create conversations with selected audiences, not simply to send payment requests to everyone.",
    "body_mk": "",
    "summary": "Choose the audience and study the supplied opener / follow-up examples.",
    "assets": [
      {
        "name": "MM1.png",
        "title": "MM1 · Wordplay opener",
        "caption": "An opener followed by three paired follow-up groups."
      },
      {
        "name": "MM2.png",
        "title": "MM2 · Pop-culture opener",
        "caption": "A pop-culture opening that develops into several follow-ups."
      },
      {
        "name": "MM3.png",
        "title": "MM3 · Secret-themed opener",
        "caption": "A curiosity-led opening and follow-up sequence. The final Discord note belongs to the source screenshot, not to EVZON support."
      },
      {
        "name": "MM4.png",
        "title": "MM4 · Anecdote structure",
        "caption": "A short story opening with explicitly labeled FU1–FU3 follow-ups."
      },
      {
        "name": "MM5.png",
        "title": "MM5 · Recurring-theme sequence",
        "caption": "Several follow-up paragraphs using one recurring theme."
      },
      {
        "name": "MM6.png",
        "title": "MM6 · Extended-metaphor sequence",
        "caption": "A single theme with explicitly labeled FU1–FU4 follow-ups."
      },
      {
        "name": "MM7.png",
        "title": "MM7 · Preference-question opener",
        "caption": "An opening question with a sequence of responses and follow-ups."
      }
    ],
    "note": "MM means mass-message example; FU means follow-up. These supplied adult examples illustrate structure, not an instruction to send every line or override a refusal. Use approved audiences, account permissions and the customer’s expressed preferences.",
    "position": 21,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 9
  },
  {
    "id": "daily-offers",
    "day": 4,
    "section": "Daily operations",
    "title": "New subscribers, pricing, custom requests and VIP",
    "title_mk": "",
    "body": "## 3. Catch and Hook — Welcoming New Subscribers\n\nThe \"Catch and Hook\" procedure explains what to do when someone new subscribes.\n\nAs soon as you receive a new subscription notification, open a conversation with the subscriber.\n\nThe first priority is to establish familiarity, not immediately sell additional content.\n\nTry to learn useful information about the customer, such as:\n\n- Their name.\n- Their age.\n- Their occupation.\n- Where they live.\n- Their interests.\n- What they enjoy discussing.\n- What type of creator content interests them.\n\nAsk questions naturally instead of making the interaction feel like an interview.\n\nFor example, start by welcoming the subscriber and asking how their day is going.\n\nContinue by learning more about them through ordinary conversation.\n\nThe training emphasizes that collecting basic information makes future conversations easier.\n\nIf you know the person's name, interests, and previous discussion topics, you can communicate in a more personal and consistent way.\n\n**Important rule: Do not immediately pitch a new subscriber.**\n\nThe first interaction should establish a connection and give the person time to become familiar with the account.\n\n## 4. Pricing — Do Not Undervalue Content\n\nOne of the central procedures is:\n\n**Pitch high. Do not underprice content.**\n\nThe training instructs chatters to follow the established pricing guidelines rather than inventing unusually low prices to secure quick sales.\n\nThe reasoning is that repeatedly selling content below its intended price reduces the value received from each purchase.\n\nIt can also create expectations that future content will be sold at similarly low prices.\n\nBefore quoting a price:\n\n1. Identify the type of content being requested.\n2. Check the established pricing guidelines.\n3. Confirm whether the content is standard or custom-made.\n4. Provide the appropriate price.\n5. Avoid promising discounts or special conditions without permission.\n\nThe video also introduces a Notion price-listing page.\n\nExample prices entered in the lesson include:\n\n| Content type | Example price |\n|---|---|\n| Topless photograph | $15–$30 |\n| Custom explicit video | $300–$800 |\n\nThese are examples recorded in the training, not universal prices for every creator.\n\n**Main principle:** Always know what the content is worth according to the creator's agreed pricing structure.\n\n## 5. Selling More Custom Content\n\nThe training recommends offering custom videos more frequently because they can produce higher-value sales.\n\nCustom content is material created specifically for an individual customer's request.\n\nUnlike existing photos and videos, custom content requires additional planning and effort from the creator.\n\nBecause of this, custom requests may be priced higher.\n\n**How to handle a custom-content request**\n\nFirst, understand what the customer wants.\n\nFind out the type of content, requested duration, and any relevant preferences.\n\nSecond, make sure the creator is willing and able to produce it.\n\nThird, check the agreed pricing and approval process.\n\nFourth, give the customer a clear price and explain what they will receive.\n\nFifth, confirm the request and arrange payment through the approved platform process.\n\nFinally, communicate the agreed delivery expectations accurately.\n\nNever promise a custom video, delivery date, or feature without the creator's authorization.\n\nThe central training point is that custom content can represent a significant source of revenue and should not be overlooked.\n\n## 6. VIP Treatment\n\nVIP treatment is a higher-value option intended for selected customers.\n\nThe lesson instructs chatters to avoid offering VIP treatment too frequently.\n\nIt also says VIP treatment should generally be presented to subscribers who have already demonstrated spending potential.\n\nThese may be people labeled as high spenders using the agency's spending-tier or emoji system.\n\n**How VIP treatment should work**\n\nIdentify an appropriate existing customer.\n\nConsider whether they have previously spent money and whether the VIP offer is relevant to their interests.\n\nExplain what the VIP option includes.\n\nOnly offer benefits that the creator has approved and can actually provide.\n\nIf the customer accepts, confirm the terms and payment.\n\n**Important:** Do not repeatedly offer VIP treatment to the same person simply because they previously spent money.\n\nThe training specifically warns against overusing this approach.\n\nThe aim is to preserve VIP treatment as a distinct offering rather than presenting it as a standard option in every conversation.",
    "body_mk": "",
    "summary": "Use the approved prices and confirm custom deliverables before promising them.",
    "assets": [],
    "note": "",
    "position": 22,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 4
  },
  {
    "id": "records-retention",
    "day": 4,
    "section": "Daily operations",
    "title": "Labels, re-engagement and retention",
    "title_mk": "",
    "body": "## 7. Labeling Customers Correctly\n\nProper customer labeling is one of the most important organizational procedures.\n\nThe training instructs chatters to spend the **first 10–15 minutes of every shift** labeling and organizing customers.\n\nThis helps the chatter quickly understand who they are speaking with.\n\nThe system uses labels and emojis, supported by information recorded in Notion.\n\nBasic information includes:\n\n- Customer name.\n- Age, where appropriately collected.\n- Country.\n- Relevant interests.\n- Customer spending category.\n- Other useful conversation notes.\n\nThe specific emoji labels should follow the agency's established Notion system.\n\n**How to organize customers**\n\nAt the beginning of the shift, open the customer list.\n\nReview recent conversations and identify subscribers who need information added or updated.\n\nApply the appropriate spending or relationship label.\n\nRecord relevant customer information in the approved system.\n\nMake sure the information is accurate and consistent.\n\nFor example, if a customer has previously purchased expensive content, the next chatter should be able to identify them as a previous high spender.\n\nIf a customer is new, their profile should indicate that the relationship is still being established.\n\n**Why labeling matters**\n\nOrganized customer records help chatters avoid repeating questions, overlooking previous purchases, or sending inappropriate offers.\n\nThey also allow multiple chatters to work on the same account while maintaining continuity.\n\nOnly collect and retain customer information needed for legitimate account operations, and follow the platform's privacy requirements.\n\n## 8. Refiltering Subscribers — Re-engaging Old Customers\n\nRefiltering means going back through previous subscribers and customers to identify people who have not been contacted recently.\n\nThe training specifically recommends reviewing old spenders throughout the following months.\n\nSomeone who stopped responding several weeks ago may still be interested in returning.\n\n**How to refilter subscribers**\n\nStart by reviewing older conversations.\n\nLook for previous customers who have become inactive.\n\nCheck what was discussed previously, including their last purchase or last response.\n\nDecide whether a follow-up is appropriate.\n\nThen send a message related to the previous interaction or a simple check-in.\n\nThe trainer explores messages asking whether someone is ignoring the creator or whether they are still friends.\n\nThese examples are intended to attract attention and restart the exchange.\n\nA less confrontational version could be:\n\n\"heyy, how have you been lately? feels like we haven't caught up in ages haha\"\n\nThe objective is to start a conversation, not immediately send another paid offer.\n\n**Main principle:** A customer becoming inactive does not automatically mean they will never return. Previous customers can be revisited through occasional, relevant follow-up messages.\n\n## 9. Whale Retention — Managing High-Spending Subscribers\n\nA \"whale\" is a customer who spends significantly more money than an average subscriber.\n\nThe training emphasizes that these customers should be treated carefully.\n\n**Do not pitch whales every single day.**\n\nEven if someone spends large amounts of money, repeatedly sending paid offers can eventually reduce their willingness to engage.\n\nThe trainer recommends spending some days simply talking to high-spending customers.\n\nThe conversation does not always need to involve selling.\n\n**How to retain high-spending customers**\n\nMaintain regular but appropriate communication.\n\nRemember previous conversation topics.\n\nRespond to their interests and questions.\n\nProvide good aftercare following purchases.\n\nAvoid filling every interaction with expensive offers.\n\nRespect the customer's spending decisions.\n\nThe training explains that this process may sometimes feel repetitive, but continued customer relationships can contribute to long-term revenue.\n\n**Main principle: Do not burn out your best customers with constant sales pressure.**\n\nHigh spenders should still receive attention and good communication on days when they do not purchase anything.",
    "body_mk": "",
    "summary": "Organize relevant notes and keep communication respectful over time.",
    "assets": [],
    "note": "",
    "position": 23,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 3
  },
  {
    "id": "daily-followups",
    "day": 4,
    "section": "Daily operations",
    "title": "Tips, unsuccessful offers and aftercare",
    "title_mk": "",
    "body": "## 10. Do Not Randomly Ask for Tips\n\nThe training advises against directly asking subscribers for tips without offering any clear value.\n\nIts reasoning is that simply requesting money can make the chatter appear needy and overly transactional.\n\nA customer may wonder why they should send additional money without receiving anything in return.\n\nInstead, the lesson encourages chatters to focus on meaningful interactions and clearly priced content or services.\n\nTips should remain voluntary.\n\nIf the account offers an approved paid service or product, the customer should understand what they are purchasing and how much it costs.\n\n**Main principle:** Do not rely on repeatedly asking customers to send money. Concentrate on the customer experience and appropriately priced offers.\n\n## 11. Use Conversational Language Instead of Repetitive Sales Commands\n\nThe lesson discourages constantly using mechanical phrases such as:\n\n\"Unlock this.\"\n\n\"Open the content.\"\n\nThese expressions make the interaction feel like a direct transaction.\n\nThe trainer explores more conversational, emotional language to make the interaction feel continuous rather than like a separate sales advertisement.\n\nThe examples include playful questions about a subscriber becoming quiet or losing interest.\n\nThe underlying writing technique is to make messages fit the tone of the conversation.\n\nHowever, content descriptions and payment requirements should remain clear, and subscribers should not be made to feel guilty for declining a purchase.\n\n**The main lesson:** Avoid repeating identical selling commands. Use natural language while being transparent about paid content.\n\n## 12. The Failed Sales Pitch Rule\n\nOne of the strictest rules in the training is:\n\n**One failed sales pitch every 24 hours.**\n\nIf a subscriber receives a paid-content offer and does not purchase it, do not repeatedly send more paid offers.\n\nWait another 24 hours before attempting a new pitch.\n\nThe trainer also instructs chatters to remove an unsuccessful paid offer from the conversation when the platform permits it.\n\nThis prevents old, unsuccessful offers from remaining in the active conversation unnecessarily.\n\n**How to handle a failed pitch**\n\nStep 1: Send an appropriate paid-content offer.\n\nStep 2: Observe the customer's response.\n\nStep 3: If they decline or do not purchase, do not immediately send another offer.\n\nStep 4: Record the unsuccessful pitch or check the previous chat history.\n\nStep 5: Continue the conversation only if the customer remains interested.\n\nStep 6: Respect the 24-hour waiting period before considering another sales pitch.\n\n**Main principle:** Do not spam subscribers with paywalled content after they have already declined or ignored an offer.\n\n## 13. Aftercare — What to Do After Selling Content\n\nAftercare is the communication that takes place following a purchase.\n\nThe lesson specifically instructs chatters to send **at least three additional conversational messages before making another sales pitch**.\n\nThis is intended to prevent conversations from becoming a continuous series of payment requests.\n\nThe trainer emphasizes that the conversation should remain natural and realistic.\n\n**How to provide aftercare**\n\nAfter a customer purchases content, acknowledge the purchase.\n\nContinue speaking with them.\n\nAsk a relevant question or respond to what they say.\n\nAllow the conversation to develop without immediately introducing another product.\n\nMake sure the customer receives what they paid for and address any issues.\n\nThe goal is to make the subscriber feel appreciated rather than ignored after spending money.\n\nAftercare is also part of customer retention.\n\nA positive purchasing experience may make someone more comfortable returning in the future.\n\nThe three-message rule is a training minimum for the example workflow, not permission to pressure someone with another offer after exactly three messages.",
    "body_mk": "",
    "summary": "Apply the failed-pitch window and the aftercare guidance.",
    "assets": [],
    "note": "Do not delete messages to conceal a complaint, payment dispute or transaction history. Any permitted unsending must follow platform policy and retain the required audit trail.",
    "position": 24,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 3
  },
  {
    "id": "shift-preparation",
    "day": 4,
    "section": "Daily operations",
    "title": "Shift preparation, tools and authorized requests",
    "title_mk": "",
    "body": "## 14. Preparing at the Start of Every Shift\n\nThe training emphasizes that every shift should begin with preparation rather than immediately sending random messages.\n\n**Step 1 — Read previous conversations**\n\nBefore replying to someone, check the existing chat history.\n\nIdentify the topic that was being discussed.\n\nCheck whether the customer has already received a paid-content offer.\n\nLook for previous questions that have not been answered.\n\n**Step 2 — Check failed pitches**\n\nIdentify customers who have recently declined or ignored a sales pitch.\n\nDo not repeat the same unsuccessful offer.\n\nMake sure the 24-hour rule is respected.\n\n**Step 3 — Review customer information**\n\nCheck customer labels, spending categories, and existing notes.\n\nUpdate any inaccurate or missing information.\n\nSpend approximately 10–15 minutes on labeling and organization.\n\n**Step 4 — Identify priority conversations**\n\nLook for new subscribers requiring a welcome.\n\nCheck customers who have recently sent messages.\n\nIdentify existing customers waiting for a reply.\n\nReview appropriate follow-up opportunities.\n\n**Step 5 — Continue naturally**\n\nWhen responding to a customer, continue from the previous conversation.\n\nDo not behave as though the conversation has started from zero if the customer has already been communicating with the account.\n\n**Main principle:** Every chatter must understand the state of a conversation before taking it over.\n\n## 15. Using Fanvue \n\nThe training uses Fanvue for conversations, customer interactions and sales-related tasks, while Notion is used to organize information and training resources.\n\n### Fanvue\n\nFanvue provides the working environment for:\n\n- Viewing and replying to messages.\n- Finding online users.\n- Creating mass messages.\n- Choosing included and excluded audience lists.\n- Reviewing subscriber categories.\n- Checking customer information.\n- Sending paid content where authorized.\n- Reviewing previous purchases and interactions.\n\nWhen creating a targeted mass message, use the audience-selection tools rather than automatically selecting every contact.\n\nAvailable audience categories can include online users, followers, active subscribers, renewing or non-renewing subscribers, and other groups.\n\n**Main principle:** Fanvue is the operational messaging platform, while Notion supports consistency, organization, and knowledge-sharing.\n\n## 16. Custom Requests and Paid Rating Services\n\nIn addition to standard photos and videos, the training briefly identifies custom content and paid rating requests as possible offerings.\n\nCustom content should have clearly agreed specifications and pricing.\n\nA paid rating service should also have a defined price and clearly described deliverable.\n\nBefore accepting either type of request, verify that it is permitted by the creator, allowed by the platform, and within the creator's boundaries.\n\nThe training does not establish a complete separate procedure or a fixed price for every type of rating request.\n\nThe main principle is to recognize additional authorized offerings without misrepresenting what the customer will receive.",
    "body_mk": "",
    "summary": "Check prior conversations, notes, offers and the approved working tools.",
    "assets": [],
    "note": "",
    "position": 25,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 2
  },
  {
    "id": "daily-checklist",
    "day": 4,
    "section": "Daily operations",
    "title": "Your complete daily checklist",
    "title_mk": "",
    "body": "## 17. Complete Daily Chatter Workflow\n\nThe SOPs can be combined into one operational routine.\n\n**Before starting conversations**\n\n1. Read previous chat histories.\n2. Check recent failed sales pitches.\n3. Spend 10–15 minutes reviewing and updating customer labels.\n4. Review relevant customer information.\n5. Check approved content pricing and creator information.\n\n**When new subscribers arrive**\n\n1. Welcome them.\n2. Start a normal conversation.\n3. Learn useful information about their interests.\n4. Establish familiarity.\n5. Avoid immediately pitching paid content.\n\n**During the shift**\n\n1. Respond to active conversations.\n2. Use targeted mass DMs where appropriate.\n3. Continue conversations naturally.\n4. Offer authorized paid content when the customer shows genuine interest.\n5. Follow the pricing guidelines.\n6. Consider custom-content requests when appropriate.\n7. Maintain relationships with previous high spenders.\n\n**When a customer declines an offer**\n\n1. Do not immediately send another.\n2. Respect the 24-hour rule.\n3. Record or review the unsuccessful pitch.\n4. Continue the conversation without pressuring the customer.\n\n**After a successful purchase**\n\n1. Acknowledge the purchase.\n2. Provide good aftercare.\n3. Continue the conversation naturally.\n4. Send at least three conversational messages before even considering another pitch, as recommended by the training.\n5. Ensure the customer receives what was purchased.\n\n**When activity becomes quieter**\n\n1. Review previous customers.\n2. Identify suitable re-engagement opportunities.\n3. Contact inactive subscribers occasionally.\n4. Check for new subscribers.\n5. Continue updating customer information.\n\n## 18. Core Rules Every Chatter Should Remember\n\n**Rule 1 — Target the correct audience.** Different subscribers require different approaches.\n\n**Rule 2 — Welcome new subscribers quickly.** Establish familiarity before introducing additional paid content.\n\n**Rule 3 — Follow pricing guidelines.** Do not undervalue products or invent unauthorized discounts.\n\n**Rule 4 — Consider approved custom-content opportunities.** These can be higher-value sales.\n\n**Rule 5 — Do not overuse VIP treatment.** Reserve it for suitable customers and follow the approved offer terms.\n\n**Rule 6 — Label customers properly.** Spend the first 10–15 minutes of every shift reviewing and organizing customer information.\n\n**Rule 7 — Re-engage previous spenders.** Occasionally revisit older conversations.\n\n**Rule 8 — Maintain high-spending relationships.** Do not pitch high spenders every day.\n\n**Rule 9 — Do not repeatedly request tips.** Focus on providing value and making clear offers.\n\n**Rule 10 — Use natural conversational language.** Avoid making every interaction sound like a sales command.\n\n**Rule 11 — Respect the failed-pitch limit.** Do not repeatedly pitch a customer within 24 hours of an unsuccessful offer.\n\n**Rule 12 — Provide aftercare.** Continue meaningful communication after purchases.\n\n**Rule 13 — Read chat history before replying.** Understand previous interactions before taking over a conversation.\n\n**Rule 14 — Use the approved agency resources.** Consult creator notes, labels, and pricing information when needed.\n\n**Rule 15 — Maintain consistency throughout the shift.** Good chatter performance requires both effective communication and organized daily operations.\n\n---\n\n## Final Summary\n\nThe Standard Operating Procedures establish a complete approach to managing creator-platform conversations.\n\nThe objective is to combine organized customer information, appropriate sales timing, consistent pricing, natural communication, and long-term customer retention.\n\nA successful chatter should know who they are talking to, what has already been discussed, what the customer has previously purchased, whether a sales pitch has recently failed, and whether a new offer is appropriate.\n\nThe most important operational formula is:\n\n**Prepare → Organize Customers → Welcome New Subscribers → Build Conversations → Identify Interest → Offer Appropriate Content → Provide Aftercare → Maintain Customer Relationships → Repeat.**\n\nConsistency in these procedures helps the team work more effectively and ensures that conversations remain organized even when multiple chatters handle the same account.",
    "body_mk": "",
    "summary": "Bring the course together in the source’s daily routine.",
    "assets": [],
    "note": "",
    "position": 26,
    "published": true,
    "revision": 1,
    "source": "Pasted text(4).txt",
    "minutes": 3
  }
]
$evzon_course$::jsonb) as x(id text,day int,section text,title text,title_mk text,summary text,body text,body_mk text,note text,assets jsonb,position int,minutes int,published boolean,revision int,source text);
update public.evzon_chatter_lessons set title='Foundations & working tools',title_mk='Основи и работни алатки',content='Start with the role, workspace, notes and the working rules. Study every chapter below, then submit the day for trainer review.',content_mk='Започнете со улогата, работниот простор, белешките и правилата. Прочитајте ги сите поглавја, па испратете го денот на проверка.' where day=1 and content='';
update public.evzon_chatter_lessons set title='Conversation paths & customer care',title_mk='Разговори и грижа за корисниците',content='Work through the conversation flow, its decision points and the no-pitch route. Mark each chapter studied before requesting review.',content_mk='Проучете го текот на разговорот, одлуките и патеката без продажна понуда. Означете ги сите поглавја пред да побарате проверка.' where day=2 and content='';
update public.evzon_chatter_lessons set title='PPV offers & aftercare',title_mk='PPV понуди и комуникација по купување',content='Study timing, clear offers and aftercare. Open the eight PPV references beside the relevant chapters. Prices in examples are not a current rate card.',content_mk='Проучете ги соодветниот момент, јасните понуди и комуникацијата по купување. Осумте PPV примери се во соодветните поглавја. Прикажаните цени не се тековен ценовник.' where day=3 and content='';
update public.evzon_chatter_lessons set title='Daily operations & difficult situations',title_mk='Дневни задачи и сложени ситуации',content='Review customer care, shift procedures and all seven mass-message examples. Prepare questions for your trainer before shadowing.',content_mk='Разгледајте ги грижата за корисници, процедурите за смена и седумте примери за масовни пораки. Подгответе прашања за обучувачот пред набљудувањето.' where day=4 and content='';
;
