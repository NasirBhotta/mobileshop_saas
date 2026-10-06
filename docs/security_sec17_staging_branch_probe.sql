-- SEC-17 staging branch baseline probe.
-- Read-only and safe for either a blank project or a branch.
-- Run this in the candidate staging project's SQL Editor.

with required_tables(table_name) as (
  values
    ('branches'), ('products'), ('inventory'), ('inventory_units'),
    ('customer_purchases'), ('accounts'), ('account_transactions'),
    ('users'), ('permissions'), ('user_branch_role_assignments')
),
table_state as (
  select
    required.table_name,
    to_regclass('public.' || required.table_name) is not null as is_present
  from required_tables required
)
select jsonb_build_object(
  'has_production_schema_baseline', (select bool_and(is_present) from table_state),
  'tables', (select jsonb_object_agg(table_name, is_present) from table_state),
  'next_action', case
    when (select bool_and(is_present) from table_state)
      then 'Run security_sec17_staging_preflight.sql next.'
    else 'Do not run SEC-17 drafts here. Create a data-less branch from the production project schema.'
  end
) as security_staging_branch_probe;
