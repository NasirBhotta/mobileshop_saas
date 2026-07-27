-- An approved credit return reverses receivable only. It never moves cash.

create table if not exists public.sale_return_credit_adjustments (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null unique
    references public.sale_returns(id) on delete restrict,
  original_sale_id uuid not null references public.sales(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_credit_return_original_sale
  on public.sale_return_credit_adjustments(original_sale_id);

alter table public.sale_return_credit_adjustments enable row level security;
drop policy if exists "branch users can read credit return adjustments"
  on public.sale_return_credit_adjustments;
create policy "branch users can read credit return adjustments"
on public.sale_return_credit_adjustments for select to authenticated
using (
  exists (
    select 1
    from public.sale_returns sale_return
    join public.branches branch on branch.id = sale_return.branch_id
    join public.users app_user on app_user.tenant_id = branch.tenant_id
    where sale_return.id = sale_return_credit_adjustments.return_id
      and app_user.id = auth.uid()
  )
);

create or replace function public.post_pos_credit_return(p_return_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_return public.sale_returns%rowtype;
  v_sale public.sales%rowtype;
  v_customer public.customers%rowtype;
  v_credit_issued numeric;
  v_credit_reversed numeric;
  v_existing public.sale_return_credit_adjustments%rowtype;
begin
  if p_return_id is null then
    raise exception using errcode = '22023',
      message = 'Return identity is required.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_return_id::text, 0));

  select adjustment.* into v_existing
  from public.sale_return_credit_adjustments adjustment
  where adjustment.return_id = p_return_id;
  if v_existing.id is not null then
    return false;
  end if;

  select sale_return.* into v_return
  from public.sale_returns sale_return
  where sale_return.id = p_return_id
  for update;
  if v_return.id is null or v_return.status <> 'approved'
     or v_return.refund_method <> 'credit'
     or v_return.refund_amount <= 0 then
    raise exception using errcode = '23514',
      message = 'Only an approved credit return can reverse receivable.';
  end if;
  if not public.current_user_has_branch_permission(
    (select branch.tenant_id from public.branches branch
     where branch.id = v_return.branch_id),
    v_return.branch_id,
    'pos.sale.return'
  ) then
    raise exception using errcode = '42501',
      message = 'POS return permission is required.';
  end if;

  select sale.* into v_sale
  from public.sales sale
  where sale.id = v_return.original_sale_id
  for update;
  if v_sale.id is null or v_sale.branch_id <> v_return.branch_id
     or v_sale.customer_id is null then
    raise exception using errcode = '22023',
      message = 'Credit return requires the original customer.';
  end if;

  select customer.* into v_customer
  from public.customers customer
  where customer.id = v_sale.customer_id
  for update;
  select coalesce(sum(payment.amount), 0) into v_credit_issued
  from public.sale_payments payment
  where payment.sale_id = v_sale.id and payment.method = 'credit';
  select coalesce(sum(adjustment.amount), 0) into v_credit_reversed
  from public.sale_return_credit_adjustments adjustment
  where adjustment.original_sale_id = v_sale.id;

  if v_credit_reversed + v_return.refund_amount > v_credit_issued + 0.01 then
    raise exception using errcode = '23514',
      message = 'Credit return exceeds original credit capacity.';
  end if;
  if v_customer.id is null
     or v_customer.outstanding_balance + 0.01 < v_return.refund_amount then
    raise exception using errcode = '23514',
      message = 'Credit return exceeds customer outstanding balance.';
  end if;

  insert into public.sale_return_credit_adjustments (
    return_id, original_sale_id, customer_id, amount
  ) values (
    v_return.id, v_sale.id, v_customer.id, v_return.refund_amount
  );
  update public.customers
  set outstanding_balance = outstanding_balance - v_return.refund_amount
  where id = v_customer.id;
  return true;
end
$function$;

revoke all on function public.post_pos_credit_return(uuid) from public, anon;
grant execute on function public.post_pos_credit_return(uuid)
  to authenticated, service_role;
