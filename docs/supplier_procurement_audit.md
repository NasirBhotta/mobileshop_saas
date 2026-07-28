# Supplier Procurement Accounting and UX Audit

Status: accounting contract, additive supplier-ledger foundation, supplier
history, legacy-balance reconciliation warning, and product-resolution
execution UI complete.

## Canonical event effects

| Event | Inventory | Supplier payable | Money account |
|---|---:|---:|---:|
| Purchase order | No change | No change | No change |
| Goods receipt | Stock/direct-use resolution | Increase | No change |
| Supplier payment | No change | Decrease | Selected account OUT |
| Purchase return | Decrease where stocked | Decrease | No immediate movement |
| Supplier credit note | No change | Decrease | No change |
| Payment reversal | No change | Increase | Original account IN |

## Confirmed current gaps

1. PO items now explicitly support existing product, create on receipt,
   resolve on receipt, and direct repair/shop use.
2. Local and remote receipt paths reject unresolved stock items and atomically
   execute product creation, stock, receipt, and payable changes.
3. The offline receipt path previously performed item, inventory, PO, receipt,
   and supplier balance writes without one explicit outer transaction. This is
   resolved and retry-tested.
4. New receipts and supplier payments now create stable supplier-ledger entries
   in the same transaction as their balance effects.
5. Receipt/payment history now has a user-facing, date-filtered statement.
   Orders are shown separately so commitments are not confused with payable.
6. A different-cost online receipt may create a product variant while the
   offline path intentionally defers stock posting, leaving no user-facing
   corruption of the original product; sync creates and refreshes the variant.

## Safe migration rules

- Make product linkage nullable only after adding an explicit resolution state.
- A stock item cannot complete receipt while unresolved.
- Product creation, stock addition, receipt rows, and payable entry must commit
  atomically.
- Direct-use items create payable/cost history but do not change inventory.
- Every receipt/payment/return/credit event uses one stable source key.
- Historical product links and supplier balances are never guessed.
- Reconciliation reports differences; it does not rewrite them silently.
