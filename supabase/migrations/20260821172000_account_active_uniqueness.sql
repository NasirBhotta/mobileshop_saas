-- Update account name uniqueness constraint to check only active accounts.
-- Allows reusing names of deleted / archived accounts without breaking
-- ledger continuity or causing sync deadlock.

create or replace function public.prevent_duplicate_account_name()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_normalized_name text;
begin
  -- Deactivated / inactive accounts do not claim active name uniqueness
  if not coalesce(new.is_active, true) then
    return new;
  end if;

  new.name := btrim(regexp_replace(new.name, '\s+', ' ', 'g'));
  if new.name = '' then
    raise exception 'ACCOUNT_NAME_REQUIRED';
  end if;

  v_normalized_name := lower(new.name);

  -- Serialize competing creates/renames for the same branch and normalized
  -- name so the application-level duplicate check cannot race.
  perform pg_advisory_xact_lock(
    hashtextextended(new.branch_id::text || ':' || v_normalized_name, 0)
  );

  if exists (
    select 1
    from public.accounts account
    where account.branch_id = new.branch_id
      and account.id <> new.id
      and account.is_active = true
      and lower(
        btrim(regexp_replace(account.name, '\s+', ' ', 'g'))
      ) = v_normalized_name
  ) then
    raise exception 'ACCOUNT_NAME_EXISTS';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_accounts_unique_name on public.accounts;
create trigger trg_accounts_unique_name
before insert or update of name, branch_id, is_active on public.accounts
for each row execute function public.prevent_duplicate_account_name();
