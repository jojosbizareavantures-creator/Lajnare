-- Add the user's original Farming and VIP images to the related existing chapters.
-- Only image metadata and estimated reading time change; keep text, revisions,
-- study records, approvals, and exam results intact. Reapplying is safe.
begin;
select pg_advisory_xact_lock(782541);
do $release$
declare patch jsonb; chapter evzon_private.training_units;
begin
 for patch in select value from jsonb_array_elements($images$[{"id":"pitch-examples","before_assets":[{"name":"ppv1.png","title":"Sending the PPV","caption":"A slide about selecting content and personalizing captions."},{"name":"ppv2.png","title":"How to write PPVs","caption":"A source checklist for writing PPV messages."},{"name":"ppv3.png","title":"Caption examples · set one","caption":"Two supplied message examples."},{"name":"ppv4.png","title":"Caption examples · set two","caption":"Three supplied message examples."}],"before_minutes":7,"revision":2,"body_hash":"f01f2e40026899c8dbf9d4d4bc692df2","translation_hash":"7c4ea1634f49c80f3697dd39c0bdff8d","assets":[{"name":"ppv1.png","title":"Sending the PPV","caption":"A slide about selecting content and personalizing captions."},{"name":"ppv2.png","title":"How to write PPVs","caption":"A source checklist for writing PPV messages."},{"name":"ppv3.png","title":"Caption examples · set one","caption":"Two supplied message examples."},{"name":"ppv4.png","title":"Caption examples · set two","caption":"Three supplied message examples."},{"name":"farm1.png","title":"How Farming Works","caption":"Farming · 1 of 5."},{"name":"farm2.png","title":"The Core of It: Emotion + Upselling","caption":"Farming · 2 of 5."},{"name":"farm3.png","title":"Key Strategies for Farming","caption":"Farming · 3 of 5."},{"name":"farm4.png","title":"What is a green light response?","caption":"Farming · 4 of 5."},{"name":"farm5.png","title":"Save the Best for Last","caption":"Farming · 5 of 5."}],"minutes":12},{"id":"daily-offers","before_assets":[],"before_minutes":4,"revision":2,"body_hash":"ea8c12d23fd1cb6e0a6686b3e357408b","translation_hash":"608df514e62bf03e3b47f88f14c11d26","assets":[{"name":"VIP1.png","title":"VIP Pitching","caption":"VIP · 1 of 5."},{"name":"VIP2.png","title":"Example Conversation","caption":"VIP · 2 of 5."},{"name":"VIP3.png","title":"Pitching the Price Properly","caption":"VIP · 3 of 5."},{"name":"VIP4.png","title":"VIP Unlock Sequence","caption":"VIP · 4 of 5."},{"name":"VIP5.png","title":"What’s the Strategy?","caption":"VIP · 5 of 5."}],"minutes":9}]$images$::jsonb) loop
  select * into chapter from evzon_private.training_units where id=patch->>'id' for update;
  if not found then raise exception 'Training chapter missing'; end if;
  if chapter.assets=patch->'assets' and chapter.minutes=(patch->>'minutes')::int then continue; end if;
  if chapter.assets is distinct from patch->'before_assets'
   or chapter.minutes is distinct from (patch->>'before_minutes')::int
   or chapter.revision is distinct from (patch->>'revision')::int
   or md5(chapter.body) is distinct from patch->>'body_hash'
   or md5(chapter.body_mk) is distinct from patch->>'translation_hash' then
   raise exception 'Training chapter % changed since review; image update cancelled',chapter.id;
  end if;
  update evzon_private.training_units set assets=patch->'assets',minutes=(patch->>'minutes')::int,updated_at=now() where id=chapter.id;
 end loop;
end $release$;
commit;
select id,day,revision,minutes,jsonb_array_length(assets) as image_count from evzon_private.training_units where id in ('pitch-examples','daily-offers') order by day;
