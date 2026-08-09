-- Preserve the cashier-selected original payment account across return approval.
-- Refunds remain capped by and linked to the original non-credit payment.

alter table public.sale_returns
  add column if not exists refund_payment_id uuid
  references public.sale_payments(id) on delete restrict;

create index if not exists idx_sale_returns_refund_payment
  on public.sale_returns(refund_payment_id)
  where refund_payment_id is not null;

comment on column public.sale_returns.refund_payment_id is
  'Original non-credit payment selected as the refund source account.';
