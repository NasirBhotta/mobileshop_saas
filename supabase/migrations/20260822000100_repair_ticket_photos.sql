-- ═══════════════════════════════════════════════════════════════════════════
-- REPAIR TICKET DEVICE PHOTOS & STORAGE BUCKET
-- ═══════════════════════════════════════════════════════════════════════════

alter table if exists public.repair_tickets
  add column if not exists photo_paths text[] not null default '{}'::text[];

-- Create storage bucket for repair photos
insert into storage.buckets (id, name, public)
values ('repair-photos', 'repair-photos', true)
on conflict (id) do update set public = true;

-- Drop old policies if they exist so we can recreate robust ones
drop policy if exists "repair_photos_tenant_read" on storage.objects;
drop policy if exists "repair_photos_tenant_insert" on storage.objects;
drop policy if exists "repair_photos_tenant_update" on storage.objects;
drop policy if exists "repair_photos_tenant_delete" on storage.objects;

-- Storage RLS Policies for tenant isolation
create policy "repair_photos_tenant_read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'repair-photos'
    and (
      (storage.foldername(name))[1] in (
        select tenant_id::text
        from public.users
        where id = auth.uid()
          and is_active = true
          and deleted_at is null
      )
      or (storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'tenant_id'::text)
    )
  );

create policy "repair_photos_tenant_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'repair-photos'
    and (
      (storage.foldername(name))[1] in (
        select tenant_id::text
        from public.users
        where id = auth.uid()
          and is_active = true
          and deleted_at is null
      )
      or (storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'tenant_id'::text)
    )
  );

create policy "repair_photos_tenant_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'repair-photos'
    and (
      (storage.foldername(name))[1] in (
        select tenant_id::text
        from public.users
        where id = auth.uid()
          and is_active = true
          and deleted_at is null
      )
      or (storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'tenant_id'::text)
    )
  );

create policy "repair_photos_tenant_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'repair-photos'
    and (
      (storage.foldername(name))[1] in (
        select tenant_id::text
        from public.users
        where id = auth.uid()
          and is_active = true
          and deleted_at is null
      )
      or (storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'tenant_id'::text)
    )
  );
