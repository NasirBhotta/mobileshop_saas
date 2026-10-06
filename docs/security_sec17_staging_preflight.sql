-- SEC-17 staging preflight for Supabase SQL Editor.
-- Read-only: this query changes no rows, schema, grants, policies or functions.
-- Run only in the isolated staging branch before any SEC-17 draft SQL.

with expected_tables(table_name) as (
  values
    ('branches'), ('products'), ('inventory'), ('inventory_units'),
    ('customer_purchases'), ('accounts'), ('account_transactions'),
    ('users'), ('permissions'), ('roles'), ('role_permissions'),
    ('user_branch_role_assignments')
),
table_state as (
  select
    expected.table_name,
    coalesce(cls.relrowsecurity, false) as rls_enabled,
    cls.oid is not null as is_present
  from expected_tables expected
  left join pg_namespace ns on ns.nspname = 'public'
  left join pg_class cls
    on cls.relnamespace = ns.oid
   and cls.relname = expected.table_name
   and cls.relkind in ('r', 'p')
),
required_functions(function_name) as (
  values
    ('current_user_has_branch_permission'),
    ('record_account_transaction_v2')
),
function_state as (
  select
    required.function_name,
    coalesce(jsonb_agg(jsonb_build_object(
      'identity_arguments', pg_get_function_identity_arguments(proc.oid),
      'security_definer', proc.prosecdef,
      'search_path', proc.proconfig
    ) order by proc.oid) filter (where proc.oid is not null), '[]'::jsonb) as overloads
  from required_functions required
  left join pg_namespace ns on ns.nspname = 'public'
  left join pg_proc proc
    on proc.pronamespace = ns.oid
   and proc.proname = required.function_name
  group by required.function_name
),
required_constraints(constraint_name) as (
  values ('inventory_units_branch_imei_key')
),
constraint_state as (
  select
    required.constraint_name,
    con.oid is not null as is_present,
    pg_get_constraintdef(con.oid, true) as definition
  from required_constraints required
  left join pg_constraint con on con.conname = required.constraint_name
),
required_indexes(index_name) as (
  values ('uq_account_transactions_source_event')
),
index_state as (
  select
    required.index_name,
    idx.indexrelid is not null as is_present,
    pg_get_indexdef(idx.indexrelid) as definition
  from required_indexes required
  left join pg_class index_class on index_class.relname = required.index_name
  left join pg_index idx on idx.indexrelid = index_class.oid
),
required_permissions(permission_key) as (
  values
    ('inventory.product.create'), ('inventory.product.update'),
    ('inventory.imei.manage'), ('account.transaction.create')
),
permission_state as (
  select
    required.permission_key,
    permission.id is not null as is_present,
    permission.is_active
  from required_permissions required
  left join public.permissions permission on permission.key = required.permission_key
)
select jsonb_build_object(
  'safe_to_apply_customer_buyin_draft',
    (select bool_and(is_present) from table_state)
    and (select bool_and(jsonb_array_length(overloads) > 0) from function_state)
    and (select bool_and(is_present) from constraint_state)
    and (select bool_and(is_present) from index_state)
    and (select bool_and(is_present and is_active) from permission_state),
  'tables', (select jsonb_agg(to_jsonb(table_state) order by table_name) from table_state),
  'functions', (select jsonb_agg(to_jsonb(function_state) order by function_name) from function_state),
  'constraints', (select jsonb_agg(to_jsonb(constraint_state) order by constraint_name) from constraint_state),
  'indexes', (select jsonb_agg(to_jsonb(index_state) order by index_name) from index_state),
  'permissions', (select jsonb_agg(to_jsonb(permission_state) order by permission_key) from permission_state)
) as security_staging_preflight;
