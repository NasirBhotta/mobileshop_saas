-- Read-only verification after applying staging_secure_pos_return_restore_draft.sql.
-- Run only in the STAGING project's SQL Editor.

with target as (
  select p.oid, n.nspname as schema_name, p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    p.prosecdef as security_definer,
    p.proconfig as config,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'restore_pos_sale_for_return'
)
select
  t.schema_name,
  t.proname,
  t.identity_arguments,
  t.security_definer,
  t.config,
  coalesce(array_agg(distinct case when x.grantee = 0 then 'PUBLIC'
    else pg_get_userbyid(x.grantee) end order by case when x.grantee = 0 then 'PUBLIC'
    else pg_get_userbyid(x.grantee) end) filter (where x.privilege_type = 'EXECUTE'),
    '{}'::text[]) as execute_grantees,
  t.definition like '%commit_pos_sale_v2%' as uses_validated_sale_commit
from target t
join pg_proc p on p.oid = t.oid
left join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x on true
group by t.oid, t.schema_name, t.proname, t.identity_arguments,
  t.security_definer, t.config, t.definition;
