# Combined POS-return migration build status

The implementation is being assembled from the confirmed staging contract.
Before it is handed over for execution, it must preserve the following
invariants in one PostgreSQL transaction:

1. `pending_approval` writes no inventory or financial rows.
2. Only `pending_approval -> approved` is permitted; approved rows are immutable.
3. Every approved return locks the original sale, original items, destination
   product and inventory rows before changing them.
4. Restock product IDs are stored on `sale_return_items`; an exact retry cannot
   create a second product or increment inventory again.
5. Cash and credit refund helpers are called only after the return/item checks,
   inside the same transaction. Any error rolls back the new parent, items,
   inventory and money movement.
6. Existing direct table policies and existing public client compatibility paths
   are unchanged in this staging phase.

Required acceptance result is one synthetic pending return, one approval,
exact approval retry, denied-user attempt, and no partial rows after a rejected
request. This will be in one test runner after the migration is prepared.