-- Run after all migrations against a disposable/local database.
begin;

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values (
  '00000000-0000-4000-8000-000000000901',
  'Subscription trigger test', 'retail', 1, 'starter', 'active', false
);

do $test$
begin
  if not exists (
    select 1
    from public.tenant_subscriptions s
    join public.plans p on p.id = s.plan_id
    where s.tenant_id = '00000000-0000-4000-8000-000000000901'
      and s.is_active and s.deleted_at is null and p.key = 'starter'
  ) then
    raise exception 'New tenant subscription was not created';
  end if;
end
$test$;

rollback;
