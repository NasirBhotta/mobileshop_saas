-- Dashboard preferences are a per-user, per-tenant, per-branch selection.
-- Remove historic selections that point at deleted, moved, or archived accounts.
with sanitized as (
  select
    preference.user_id,
    preference.branch_id,
    array(
      select account_id
      from unnest(preference.selected_account_ids) as account_id
      join public.accounts as account on account.id = account_id
      where account.tenant_id = preference.tenant_id
        and account.branch_id = preference.branch_id
        and account.is_active = true
      limit 2
    ) as account_ids
  from public.user_branch_dashboard_preferences as preference
), removed as (
  delete from public.user_branch_dashboard_preferences as preference
  using sanitized
  where preference.user_id = sanitized.user_id
    and preference.branch_id = sanitized.branch_id
    and cardinality(sanitized.account_ids) = 0
  returning preference.user_id, preference.branch_id
)
update public.user_branch_dashboard_preferences as preference
set selected_account_ids = sanitized.account_ids,
    updated_at = now()
from sanitized
where preference.user_id = sanitized.user_id
  and preference.branch_id = sanitized.branch_id
  and cardinality(sanitized.account_ids) between 1 and 2;

create or replace function public.validate_dashboard_preference_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if cardinality(new.selected_account_ids) not between 1 and 2 then
    raise exception 'Select one or two dashboard accounts.';
  end if;

  if exists (
    select 1
    from unnest(new.selected_account_ids) as selected(account_id)
    left join public.accounts as account
      on account.id = selected.account_id
      and account.tenant_id = new.tenant_id
      and account.branch_id = new.branch_id
      and account.is_active = true
    where account.id is null
  ) then
    raise exception 'Dashboard accounts must be active accounts in this branch.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_dashboard_preference_accounts
  on public.user_branch_dashboard_preferences;

create trigger validate_dashboard_preference_accounts
before insert or update of tenant_id, branch_id, selected_account_ids
on public.user_branch_dashboard_preferences
for each row execute function public.validate_dashboard_preference_accounts();
