-- Security Patch 10: customer access remains tenant-wide, while every customer
-- branch must belong to the same tenant. Existing inconsistent rows are never
-- modified automatically.

do $preflight$
declare
  mismatch_count bigint;
  sample_customer_ids text;
begin
  select count(*)
  into mismatch_count
  from public.customers c
  left join public.branches b on b.id = c.branch_id
  where b.id is null
     or b.tenant_id is distinct from c.tenant_id;

  if mismatch_count > 0 then
    select string_agg(id::text, ', ' order by id::text)
    into sample_customer_ids
    from (
      select c.id
      from public.customers c
      left join public.branches b on b.id = c.branch_id
      where b.id is null
         or b.tenant_id is distinct from c.tenant_id
      order by c.id
      limit 10
    ) mismatches;

    raise exception using
      errcode = '23514',
      message = format(
        'Security Patch 10 aborted: %s customer rows have mismatched tenant_id/branch_id. Sample customer IDs: %s',
        mismatch_count,
        coalesce(sample_customer_ids, '(none)')
      ),
      hint = 'Review and correct the reported rows explicitly before applying this migration; no data was modified.';
  end if;
end
$preflight$;

-- Replace every existing customer policy so no older permissive ALL/DELETE
-- policy can combine with the explicit policies below.
do $policies$
declare
  existing_policy record;
begin
  for existing_policy in
    select p.polname
    from pg_catalog.pg_policy p
    where p.polrelid = 'public.customers'::regclass
  loop
    execute format(
      'drop policy %I on public.customers',
      existing_policy.polname
    );
  end loop;
end
$policies$;

create policy "tenant users can read consistent customers"
on public.customers
for select
to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1
    from public.branches b
    where b.id = customers.branch_id
      and b.tenant_id = customers.tenant_id
  )
);

create policy "tenant users can insert consistent customers"
on public.customers
for insert
to authenticated
with check (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1
    from public.branches b
    where b.id = customers.branch_id
      and b.tenant_id = customers.tenant_id
  )
);

create policy "tenant users can update consistent customers"
on public.customers
for update
to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1
    from public.branches b
    where b.id = customers.branch_id
      and b.tenant_id = customers.tenant_id
  )
)
with check (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1
    from public.branches b
    where b.id = customers.branch_id
      and b.tenant_id = customers.tenant_id
  )
);

-- Intentionally no DELETE policy. RLS state and table grants are unchanged.
