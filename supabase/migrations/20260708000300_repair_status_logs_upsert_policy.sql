-- Repair offline sync uses upsert for status logs. Upsert can take the
-- update path when the log already exists, so repair_status_logs needs
-- an update policy in addition to select/insert.

drop policy if exists "tenant users can update repair status logs" on public.repair_status_logs;
create policy "tenant users can update repair status logs"
on public.repair_status_logs
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_status_logs.branch_id
      and u.tenant_id = repair_status_logs.tenant_id
  )
)
with check (
  changed_by = auth.uid()
  and exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_status_logs.branch_id
      and u.tenant_id = repair_status_logs.tenant_id
  )
);
