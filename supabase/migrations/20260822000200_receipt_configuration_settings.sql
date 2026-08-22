-- Add receipt_config column to tenant_settings for thermal receipt layout customization
alter table if exists public.tenant_settings
add column if not exists receipt_config text;
