-- Run against a disposable/local database after applying all migrations.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000111',
  'authenticated', 'authenticated', 'lifecycle@example.invalid', '', now(),
  '{}', '{}', now(), now(), '', '', '', ''
);

insert into public.users (id, full_name, email, role) values (
  '00000000-0000-4000-8000-000000000111',
  'Lifecycle Owner', 'lifecycle@example.invalid', 'owner'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000111',
  true
);

do $test$
declare account jsonb;
begin
  account := public.current_account_context();
  if account->>'exists' <> 'true' or account->>'is_active' <> 'true' then
    raise exception 'Active account context was not returned: %', account;
  end if;
end
$test$;

reset role;
update public.users
set is_active = false, deleted_at = now()
where id = '00000000-0000-4000-8000-000000000111';

set local role authenticated;

do $test$
declare
  account jsonb;
  visible_profiles integer;
begin
  account := public.current_account_context();
  if account->>'exists' <> 'true' or account->>'is_active' <> 'false' then
    raise exception 'Revoked account context was not returned: %', account;
  end if;

  select count(*) into visible_profiles
  from public.users
  where id = auth.uid();
  if visible_profiles <> 0 then
    raise exception 'Revoked profile remained visible to its user';
  end if;
end
$test$;

rollback;
