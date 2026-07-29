-- commit_customer_settlement inserts the settlement before its matching ledger
-- row in the same database transaction. Defer the FK check until commit so the
-- complete atomic operation is validated instead of rejecting the first insert.
alter table public.customer_settlements
  alter constraint customer_settlements_ledger_transaction_id_fkey
  deferrable initially deferred;
