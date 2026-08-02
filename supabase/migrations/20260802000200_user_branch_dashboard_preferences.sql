create table if not exists public.user_branch_dashboard_preferences (
  user_id uuid not null references public.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  selected_account_ids uuid[] not null default '{}'::uuid[],
  updated_at timestamptz not null default now(),
  primary key (user_id, branch_id),
  constraint dashboard_selected_accounts_limit
    check (cardinality(selected_account_ids) between 1 and 2)
);

alter table public.user_branch_dashboard_preferences enable row level security;

create policy "users manage own branch dashboard preferences"
on public.user_branch_dashboard_preferences
for all to authenticated
using (
  user_id = auth.uid()
  and tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
)
with check (
  user_id = auth.uid()
  and tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
);

revoke all on table public.user_branch_dashboard_preferences from anon;
grant select, insert, update, delete
on table public.user_branch_dashboard_preferences to authenticated;
