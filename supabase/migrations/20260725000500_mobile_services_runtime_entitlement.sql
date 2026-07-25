-- Register Mobile Services as a package-controlled runtime module.

insert into public.features (
  key, module, name, description, is_active
)
values (
  'mobile_services.access',
  'mobile_services',
  'Mobile Services',
  'Easypaisa and JazzCash send/receive services.',
  true
)
-- features.key is protected by a case-insensitive expression index
-- (lower(key)), not by a plain UNIQUE(key) constraint.
on conflict (lower(key)) do update
set module = excluded.module,
    name = excluded.name,
    description = excluded.description,
    is_active = excluded.is_active,
    deleted_at = null;

insert into public.plan_features (
  plan_id, feature_id, enabled, reason
)
select
  p.id,
  f.id,
  true,
  'Mobile Services initial rollout'
from public.plans p
join public.features f on lower(f.key) = 'mobile_services.access'
where lower(p.key) in ('starter', 'business', 'enterprise')
  and p.is_active
  and p.deleted_at is null
on conflict (plan_id, feature_id) do update
set enabled = excluded.enabled,
    reason = excluded.reason,
    is_active = true,
    deleted_at = null;
