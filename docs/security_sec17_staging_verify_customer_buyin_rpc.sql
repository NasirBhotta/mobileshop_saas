-- SEC-17 staging-only, read-only verification of commit_customer_buyin_v2.
-- Makes no data, schema, grant or policy change.

with target as (
  select
    proc.oid,
    namespace.nspname as schema_name,
    proc.proname,
    pg_get_function_identity_arguments(proc.oid) as identity_arguments,
    proc.prosecdef as security_definer,
    proc.proconfig as config,
    pg_get_functiondef(proc.oid) as definition,
    proc.proacl,
    proc.proowner
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'commit_customer_buyin_v2'
)
select
  target.schema_name,
  target.proname,
  target.identity_arguments,
  target.security_definer,
  target.config,
  coalesce(
    array_agg(distinct case
      when acl_entry.grantee = 0 then 'PUBLIC'
      else pg_get_userbyid(acl_entry.grantee)
    end order by case
      when acl_entry.grantee = 0 then 'PUBLIC'
      else pg_get_userbyid(acl_entry.grantee)
    end) filter (where acl_entry.privilege_type = 'EXECUTE'),
    '{}'::text[]
  ) as execute_grantees,
  position('record_account_transaction_v2' in target.definition) > 0
    as uses_idempotent_ledger_primitive
from target
left join lateral aclexplode(coalesce(target.proacl, acldefault('f', target.proowner))) acl_entry on true
group by target.oid, target.schema_name, target.proname,
  target.identity_arguments, target.security_definer, target.config, target.definition
order by target.proname;
