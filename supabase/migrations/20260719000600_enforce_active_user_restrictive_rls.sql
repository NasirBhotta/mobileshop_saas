-- PostgreSQL ORs permissive policies. Make account activity a mandatory guard
-- even if an older or environment-specific users policy is still present.

drop policy if exists "users_active_account_guard" on public.users;
create policy "users_active_account_guard"
on public.users
as restrictive
for all
to authenticated
using (
  is_active = true
  and deleted_at is null
)
with check (
  is_active = true
  and deleted_at is null
);
