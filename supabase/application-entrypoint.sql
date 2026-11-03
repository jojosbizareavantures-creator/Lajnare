-- Public candidates now use the server-validated, signed submission endpoint.
-- Keep the private implementation for referral attribution inside submit_application.
revoke execute on function public.evzon_apply(text,jsonb),evzon_private.apply(text,jsonb) from public,anon,authenticated;
