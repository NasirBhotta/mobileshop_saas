drop function if exists public.bulk_update_product_prices(uuid[], numeric, text);

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
