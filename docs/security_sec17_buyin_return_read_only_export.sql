-- Read-only focused export for the remaining SEC-17 buy-in/return staging work.
-- Safe in the live Supabase SQL Editor: this is one SELECT only.
with functions_export as (
  select p.oid, n.nspname as schema_name, p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    p.prosecdef as security_definer, p.proconfig as config,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = any(array[
    'record_account_transaction_v2','record_account_transaction',
    'post_pos_return_refund','post_pos_credit_return'
  ])
),
unit_constraints as (
  select con.conname as constraint_name, pg_get_constraintdef(con.oid, true) as definition
  from pg_constraint con join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'inventory_units'
),
unit_triggers as (
  select t.tgname as trigger_name, pg_get_triggerdef(t.oid, true) as definition
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'inventory_units' and not t.tgisinternal
),
account_columns as (
  select table_name, column_name, data_type, is_nullable, column_default
  from information_schema.columns
  where table_schema = 'public' and table_name = any(array['accounts','account_transactions'])
),
return_policies as (
  select tablename, policyname, cmd, roles, qual, with_check
  from pg_policies where schemaname = 'public'
    and tablename = any(array['sale_returns','sale_return_items','customer_purchases','inventory_units'])
)
select jsonb_build_object(
  'exported_at', now(),
  'functions', coalesce((select jsonb_agg(to_jsonb(x) order by x.proname) from functions_export x), '[]'::jsonb),
  'inventory_unit_constraints', coalesce((select jsonb_agg(to_jsonb(x) order by x.constraint_name) from unit_constraints x), '[]'::jsonb),
  'inventory_unit_triggers', coalesce((select jsonb_agg(to_jsonb(x) order by x.trigger_name) from unit_triggers x), '[]'::jsonb),
  'account_columns', coalesce((select jsonb_agg(to_jsonb(x) order by x.table_name, x.column_name) from account_columns x), '[]'::jsonb),
  'policies', coalesce((select jsonb_agg(to_jsonb(x) order by x.tablename, x.policyname) from return_policies x), '[]'::jsonb)
) as security_metadata_export;
