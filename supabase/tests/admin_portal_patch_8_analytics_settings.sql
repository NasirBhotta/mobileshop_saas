-- Run after all migrations against a disposable/local database.
begin;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)values
('00000000-0000-0000-0000-000000000000','00000000-0000-4000-8000-000000000801','authenticated','authenticated','admin-p8@example.invalid','',now(),'{}','{}',now(),now(),'','','',''),
('00000000-0000-0000-0000-000000000000','00000000-0000-4000-8000-000000000802','authenticated','authenticated','user-p8@example.invalid','',now(),'{}','{}',now(),now(),'','','','');
insert into public.platform_admins(user_id)values('00000000-0000-4000-8000-000000000801');
set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
do $test$
declare
  analytics_before jsonb;
  analytics_after jsonb;
  settings record;
  unpaid_invoice_count bigint;
begin
  analytics_before := public.platform_get_analytics();
  unpaid_invoice_count := (analytics_before->>'unpaid_invoice_count')::bigint;

  if not (analytics_before?'tenant_growth')
     or not (analytics_before?'monthly_revenue')
     or not (analytics_before?'addon_usage') then
    raise exception 'Analytics payload incomplete';
  end if;

  perform public.platform_update_settings(
    21, 5, 'annual', 'USD', 'support@example.com', '+1-555-0100',
    true, 'Scheduled maintenance'
  );
  select * into settings from public.platform_get_settings();
  if settings.trial_duration_days<>21
     or settings.default_currency<>'USD'
     or not settings.maintenance_mode then
    raise exception 'Settings update failed';
  end if;

  analytics_after := public.platform_get_analytics();
  if (analytics_after->>'unpaid_invoice_count')::bigint<>unpaid_invoice_count then
    raise exception 'Settings unexpectedly changed billing records';
  end if;

  if not exists(
    select 1 from public.platform_list_audit_logs(
      null, 'platform.settings_updated',
      '00000000-0000-4000-8000-000000000801', null, null, 20
    )
  ) then
    raise exception 'Settings audit missing';
  end if;
end
$test$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);do $test$begin begin perform public.platform_get_analytics();raise exception 'Non-admin analytics succeeded';exception when insufficient_privilege then if sqlstate<>'42501'then raise;end if;end;begin perform public.platform_get_settings();raise exception 'Non-admin settings succeeded';exception when insufficient_privilege then if sqlstate<>'42501'then raise;end if;end;end $test$;
rollback;
