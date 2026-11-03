begin;
select pg_advisory_xact_lock(782541);
update evzon_private.training_units set published=true,updated_at=now() where source='supplement-2026-10-25.txt' and revision=1 and id in ('mm-catalog','fan-preferences','fan-psychology','ppv-momentum','fan-welcome','ppv-caption-details','session-finish','objections','code-games');
select day,count(*) chapters,count(*) filter(where published) published,count(*) filter(where body_mk<>'' and title_mk<>'') translated from evzon_private.training_units group by day order by day;
commit;
