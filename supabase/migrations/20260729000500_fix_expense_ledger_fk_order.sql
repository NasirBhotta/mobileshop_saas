-- Expense posting writes the expense row before its account transaction.
-- Defer both ledger foreign keys so the atomic RPC can finish creating every
-- referenced transaction before PostgreSQL validates the relationship.

alter table public.expenses
  alter constraint expenses_ledger_transaction_id_fkey
  deferrable initially deferred;

alter table public.expenses
  alter constraint expenses_reversal_ledger_transaction_id_fkey
  deferrable initially deferred;
