-- The deployed commit_pos_sale_v2 function may link a sale payment immediately
-- before inserting its ledger row in the same transaction. Defer this FK check
-- until transaction commit so both the old and corrected function are atomic.
alter table public.sale_payments
  alter constraint sale_payments_ledger_transaction_id_fkey
  deferrable initially deferred;
