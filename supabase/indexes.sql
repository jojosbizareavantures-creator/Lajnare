create index evzon_audit_actor_idx on evzon_private.audit(actor);
create index evzon_audit_date_idx on evzon_private.audit(created_at desc);
create index evzon_payouts_admin_idx on evzon_private.payouts(paid_by);
create index evzon_periods_admin_idx on evzon_private.periods(finalized_by);
create index evzon_workday_admin_idx on evzon_private.workday_exceptions(approved_by);
create index evzon_rewards_approval_idx on public.evzon_rewards(approved_by);
create index evzon_rewards_payment_idx on public.evzon_rewards(paid_by);
create index evzon_workspace_editor_idx on public.evzon_workspace(updated_by);
