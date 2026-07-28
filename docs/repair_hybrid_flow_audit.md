# Hybrid Repair Accounting Audit

## Current implementation findings

- `total_cost` is used as the customer repair charge, despite its cost-like
  name.
- `parts_cost` and `labor_cost` exist but are not connected to item-level
  inventory or direct-purchase evidence.
- Completing a ticket currently updates ticket status/amount and a status log;
  it does not atomically consume inventory or snapshot gross profit.
- Repair payments correctly move the selected account independently.
- Reports currently treat completed/delivered `total_cost` as repair revenue,
  but do not subtract item-level repair direct costs.
- No repair delete API exists. Financial hard deletion must remain prohibited;
  future removal from operational lists will be archival.

## Target event rules

| Event | Inventory | Revenue/cost | Receivable | Money |
|---|---:|---:|---:|---:|
| Create/receive ticket | none | none | none | none |
| Complete | consume inventory parts | finalize snapshots | create balance | none |
| Receive payment | none | none | reduce balance | account IN |
| Deliver | none | none | none | none |
| Cancel before completion | release reservations | none | none | refund separately |
| Cancel after completion | restore consumed parts | reverse snapshots | reverse balance | refund separately |
| Archive | none | none | none | none |

Original financial rows and compensating reversal rows are immutable audit
evidence. Cancellation never silently deletes payments, supplier activity, or
account ledger entries.

## Implementation status

- Hybrid inventory/direct-purchase completion is active in the UI.
- Direct purchase explicitly chooses cost-already-recorded or supplier payable.
- Supplier-payable completion and cancellation create opposite statement
  entries; supplier payment remains the only account OUT event.
- Archive hides operational tickets without deleting financial evidence.
- P&L gross profit reads immutable completion/reversal snapshots, including
  repair direct costs.
