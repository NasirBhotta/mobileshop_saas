-- Security Patch 9: remove only exactly-equivalent duplicate permissive ALL
-- policies. Canonical policy definitions and RLS state remain unchanged.

do $security_patch$
declare
  table_names constant text[] := array[
    'expense_categories',
    'expenses',
    'recurring_expense_rules'
  ];
  table_name text;
  canonical_name text;
  canonical_qual text;
  canonical_with_check text;
  duplicate record;
  management_policy_count integer;
begin
  foreach table_name in array table_names loop
    canonical_name := case table_name
      when 'expense_categories' then
        'tenant users can manage expense categories'
      when 'expenses' then
        'tenant users can manage expenses'
      when 'recurring_expense_rules' then
        'tenant users can manage recurring expense rules'
    end;

    select p.polqual::text, p.polwithcheck::text
    into canonical_qual, canonical_with_check
    from pg_catalog.pg_policy p
    join pg_catalog.pg_class c on c.oid = p.polrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = table_name
      and p.polname = canonical_name
      and p.polcmd = '*'
      and p.polpermissive;

    if not found then
      raise exception
        'Security Patch 9 aborted: canonical ALL policy % is missing on public.%',
        canonical_name,
        table_name;
    end if;

    -- Drop only policies whose internal expression trees exactly match the
    -- canonical USING and WITH CHECK expressions. Role-list differences do not
    -- change effective authenticated access because the canonical policy is TO
    -- PUBLIC and remains in place.
    for duplicate in
      select p.polname
      from pg_catalog.pg_policy p
      join pg_catalog.pg_class c on c.oid = p.polrelid
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = table_name
        and p.polname <> canonical_name
        and p.polcmd = '*'
        and p.polpermissive
        and p.polqual::text is not distinct from canonical_qual
        and p.polwithcheck::text is not distinct from canonical_with_check
    loop
      execute format(
        'drop policy %I on public.%I',
        duplicate.polname,
        table_name
      );
    end loop;

    select count(*)
    into management_policy_count
    from pg_catalog.pg_policy p
    join pg_catalog.pg_class c on c.oid = p.polrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = table_name
      and p.polcmd = '*'
      and p.polpermissive;

    if management_policy_count <> 1 then
      raise exception
        'Security Patch 9 aborted: public.% has % permissive ALL policies; a non-equivalent policy was not removed',
        table_name,
        management_policy_count;
    end if;
  end loop;
end
$security_patch$;

-- Rollback is deployment-specific because duplicate policy names come from the
-- deployed catalog. Recreate only the dropped names using the same canonical
-- USING/WITH CHECK expressions if this diagnostic duplication is required.
