create extension if not exists pgcrypto;

create table if not exists public.product_price_history (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  tenant_id uuid not null,
  branch_id uuid not null,
  old_price numeric(12, 2) not null,
  new_price numeric(12, 2) not null,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  change_source text not null default 'single_update',
  check (old_price >= 0),
  check (new_price >= 0)
);

create index if not exists product_price_history_product_changed_at_idx
  on public.product_price_history(product_id, changed_at desc);

alter table public.product_price_history enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'product_price_history'
      and policyname = 'product_price_history_select_own_tenant'
  ) then
    create policy "product_price_history_select_own_tenant"
      on public.product_price_history
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and u.tenant_id = product_price_history.tenant_id
        )
      );
  end if;
end $$;

create or replace function public.prevent_product_price_history_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Product price history is append-only';
end;
$$;

drop trigger if exists product_price_history_no_update on public.product_price_history;
create trigger product_price_history_no_update
  before update on public.product_price_history
  for each row execute function public.prevent_product_price_history_mutation();

drop trigger if exists product_price_history_no_delete on public.product_price_history;
create trigger product_price_history_no_delete
  before delete on public.product_price_history
  for each row execute function public.prevent_product_price_history_mutation();

create or replace function public.record_product_sale_price_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.sale_price is distinct from old.sale_price then
    insert into public.product_price_history (
      product_id,
      tenant_id,
      branch_id,
      old_price,
      new_price,
      changed_by,
      change_source
    )
    values (
      old.id,
      old.tenant_id,
      old.branch_id,
      old.sale_price,
      new.sale_price,
      auth.uid(),
      coalesce(current_setting('app.price_change_source', true), 'single_update')
    );
  end if;

  return new;
end;
$$;

drop trigger if exists products_sale_price_history on public.products;
create trigger products_sale_price_history
  after update of sale_price on public.products
  for each row execute function public.record_product_sale_price_history();

create or replace function public.bulk_update_product_prices(
  p_product_ids text[],
  p_percentage numeric,
  p_direction text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_branch_id uuid;
  v_updated_count integer := 0;
  v_multiplier numeric;
begin
  if v_user_id is null then
    raise exception 'User not authenticated';
  end if;

  if p_product_ids is null or array_length(p_product_ids, 1) is null then
    raise exception 'No products selected';
  end if;

  if p_percentage <= 0 then
    raise exception 'Percentage must be greater than zero';
  end if;

  if p_direction not in ('markup', 'markdown') then
    raise exception 'Direction must be markup or markdown';
  end if;

  if p_direction = 'markdown' and p_percentage >= 100 then
    raise exception 'Markdown must be less than 100 percent';
  end if;

  select u.tenant_id, u.branch_id
    into v_tenant_id, v_branch_id
  from public.users u
  where u.id = v_user_id;

  if v_tenant_id is null then
    raise exception 'User tenant not found';
  end if;

  if v_branch_id is null then
    select b.id
      into v_branch_id
    from public.branches b
    where b.tenant_id = v_tenant_id
    order by b.id
    limit 1;
  end if;

  if v_branch_id is null then
    raise exception 'Branch not found';
  end if;

  v_multiplier :=
    case p_direction
      when 'markup' then 1 + (p_percentage / 100)
      else 1 - (p_percentage / 100)
    end;

  perform set_config('app.price_change_source', 'bulk_update', true);

  update public.products
  set sale_price = round((sale_price * v_multiplier)::numeric, 2)
  where id::text = any(p_product_ids)
    and tenant_id = v_tenant_id
    and branch_id = v_branch_id
    and is_active = true;

  get diagnostics v_updated_count = row_count;
  return v_updated_count;
end;
$$;

grant execute on function public.bulk_update_product_prices(text[], numeric, text)
  to authenticated;

create or replace function public.product_has_active_imei_units(p_product_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_units boolean := false;
begin
  if to_regclass('public.inventory_units') is null then
    return false;
  end if;

  begin
    execute
      'select exists (
        select 1
        from public.inventory_units
        where product_id = $1
          and imei is not null
          and btrim(imei::text) <> ''''
          and coalesce(is_sold, false) = false
      )'
      into v_has_units
      using p_product_id;
  exception
    when undefined_column then
      return false;
  end;

  return coalesce(v_has_units, false);
end;
$$;

grant execute on function public.product_has_active_imei_units(uuid)
  to authenticated;
