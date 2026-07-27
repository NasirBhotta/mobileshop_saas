# Dashboard Financial Phase 2 — Ledger Integration Audit

Status: implementation and final ledger cutover completed.

The migrations are additive and do not rewrite historical balances. New
financial events use the ledger contract; historical discrepancies remain
visible through reconciliation diagnostics rather than being auto-repaired.

## Accounting boundary

- `accounts.current_balance` is the current position of one monetary account.
- Consolidated available money is the sum of eligible active account balances.
- External inflows and outflows participate in consolidated cash flow.
- Transfers between the business's own accounts affect individual balances but
  are excluded from consolidated cash flow and profit.
- Sales, cash flow, receivables, and profit are separate measures.

The executable version of these definitions is in
`lib/features/dashboard/domain/dashboard_financial_contract.dart`.

## Current ledger foundation

| Capability | Current state | Evidence | Assessment |
|---|---|---|---|
| Branch default cash account | Accounts repository creates `Cash in Shop` with `isDefault: true` | `accounts_repository.dart` | Reusable as the initial drawer selector |
| Generic account entry | `record_account_transaction` inserts a ledger row and updates `current_balance` | `20260709000200_account_module.sql` | Remote retry is idempotent only when the same transaction UUID is reused |
| Account transfer | Two linked entries use `transfer_group_id` | `20260709000200_account_module.sql` | Correct accounting shape; integrity gaps listed below |
| Mobile Services | Cash and provider-wallet entries are written atomically with the business transaction | `20260725000300_mobile_services_transactions.sql` | Connected |
| Mobile Services void | Reversing ledger entries are created and repeated void is ignored | `20260725000400_mobile_services_void_reports.sql` | Connected and idempotent |

## Source-to-ledger reconciliation matrix

| Source event | Expected account effect | Current automatic ledger posting | Reversal/void behavior | Phase 2 result |
|---|---|---|---|---|
| POS cash/wallet/card payment | Selected monetary account IN | Atomic online and offline posting with stable payment/ledger IDs | Return exists separately | Connected and idempotent |
| POS credit sale/return | Credit issue increases receivable; approved credit return decreases it without cash movement | Stable return adjustment marker prevents replay; original credit capacity and customer outstanding are enforced | Credit return is a receivable reversal, not a cash refund | Connected and idempotent |
| Customer settlement | Selected monetary account IN; receivable decreases | Atomic local/remote settlement, customer balance, ledger, and account update | Stable settlement/ledger IDs make retries idempotent | Connected and idempotent |
| Cash sale refund | Original payment accounts OUT | Approved refund allocates across original non-credit payment legs and posts atomic OUT entries | Retry reuses stable refund/ledger IDs | Connected and idempotent |
| Confirmed expense | Selected paying account OUT | Direct-confirm and draft-confirm post atomically with stable ledger ID | Void creates an opposite IN reversal linked to the original | Connected and idempotent |
| Explicit repair payment | Selected receiving account IN; repair balance decreases | Atomic local/remote payment and ledger posting with stable IDs; completion itself has no cash movement | Retry is idempotent; no payment void/refund lifecycle exists | Connected and idempotent |
| Supplier payment | Selected paying account OUT; supplier payable decreases | Atomic local/remote supplier payment, payable, ledger, and account update | Stable payment/ledger IDs support retry reconciliation; no void lifecycle exists | Connected and idempotent |
| Mobile Service send | Cash account IN; provider wallet OUT | Yes | Explicit reversing entries | Connected |
| Mobile Service receive | Cash account OUT; provider wallet IN | Yes | Explicit reversing entries | Connected |
| Own-account transfer | Source OUT; destination IN; consolidated flow zero | Yes | No reversal workflow found | Partially connected |
| Manual account adjustment | Selected account IN/OUT | Yes | No explicit reversal link | Connected but weakly classified |

## Blocking integrity findings

### P0 — Ledger completeness — RESOLVED FOR NEW EVENTS

Manual Accounts entries/transfers, Mobile Services, non-credit POS sale
payments, approved cash refunds, and customer settlements now automatically
update the account ledger. Confirmed expenses and their void reversals are also
connected. Supplier and explicit repair payments are now connected as well.
Approved credit returns now reverse customer receivables without touching cash.
The dashboard now reads drawer/available balances from Accounts and Today
inflow/outflow/net movement from non-transfer ledger legs. No source-table cash
reconstruction remains in the dashboard or local cash-flow report.

### P0 — Generic local account application is not idempotent — RESOLVED

`AccountsLocalStore.applyTransaction` performs `INSERT OR REPLACE` and always
applies the balance delta. Calling it twice with the same transaction ID
replaces the row but increments/decrements the account twice.

Resolved in Phase 3A: financial application now uses insert-only semantics,
checks the stable transaction ID, and updates the ledger row and balance inside
one local database transaction. Transfers apply both legs atomically, repeated
stable IDs are no-ops, and partial local transfer state fails reconciliation
instead of applying another delta.

### P0 — Local transfers validate less than remote transfers — RESOLVED

The repository loads both accounts and updates them locally before the remote
RPC validates tenant, branch, active state, and distinct accounts. A locally
cached cross-branch/cross-tenant or inactive account selection can alter local
balances and then remain in a permanently failing mutation queue.

Resolved in Phase 3B: local application and the additive hardened transfer RPC
now require distinct accounts and ledger IDs, positive matching amounts,
matching transfer groups and reciprocal legs, active accounts in the requested
tenant/branch, and sufficient source balance. Local checks run before mutation;
the remote function serializes stable retries and locks both account rows before
checking and updating their balances.

### P1 — Source identity is not unique — RESOLVED

Generic ledger entries have `reference_type` and `reference_id`, but there is no
unique source-event constraint. Two different transaction UUIDs can post the
same business event twice.

Resolved in Phase 3C: nullable `source_event_key` is uniquely scoped by
tenant/branch locally and remotely, with no historical backfill. Stable
source-event retries are serialized by the v2 RPC and produce one balance
movement even if a retry carries a different transaction UUID. Nullable
`reversal_of_transaction_id` adds a restricted self-reference, one-reversal
uniqueness, and full amount/opposite-direction/context validation.

### P1 — Account transaction RLS is tenant-wide — RESOLVED

The current policy allows tenant users to manage all tenant account
transactions; it does not enforce branch assignment or granular account
permissions. Security-definer RPCs also establish tenant membership but do not
use the newer branch-aware permission model.

Resolved in Phase 3D: the database-side permission evaluator mirrors the app's
owner, legacy-fallback, active-branch-role, and per-branch override precedence.
Account transaction RPCs require branch-scoped create permission. Account RLS
separates view/create/update permissions, ledger rows are read-only through
RLS, and writes must use audited RPCs. Client guards run before cached reads or
offline-first mutations so unauthorized local data is neither exposed nor
changed before a server rejection.

### P1 — Transfers lack a group-level uniqueness invariant — RESOLVED

The hardened transfer RPC and diagnostics enforce one matching OUT/IN pair per
stable transfer group and reject partial or mismatched local state.

### P1 — Payment mode is not an account — RESOLVED FOR NEW EVENTS

POS receipts/refunds, settlements, expenses, supplier payments, and repair
receipts select a compatible account and retain stable source/ledger linkage.
Legacy nullable rows remain detectable rather than receiving a guessed account.

### P1 — Repair charge and receipt were conflated — RESOLVED

Repair analytics may report earned charges from `total_cost`; cash-flow reports
use only explicit `repair_payment` ledger receipts. A refund/void action is not
offered until that lifecycle is explicitly designed.

### P2 — Reports calculated cash flow independently — RESOLVED

Dashboard Today and local/remote cash-flow reports aggregate the account ledger,
exclude own-account transfers, and use the same inflow/outflow classification.

## Reconciliation gates before Phase 3 activation

1. The ledger balance must equal opening balance plus all non-reversed ledger
   legs for every account.
2. Every connected source event must map to at most one canonical ledger event.
3. Every void must have an auditable reversal; financial history is not deleted.
4. Every own-account transfer has exactly one OUT and one IN leg of equal value.
5. Consolidated transfer contribution is zero.
6. Offline replay produces the same balances as one online execution.
7. Tenant, branch, account status, and permissions are validated identically
   locally and remotely.
8. Dashboard Today and Reports Today use the same business timezone and source.

Phase 3E status: gates 1–7 now have read-only diagnostics. Per-account
reconciliation compares stored balance with opening balance plus signed ledger
movement. The integrity summary detects balance discrepancies, incomplete
transfer groups, duplicate source events, cross-context ledger links, and
invalid reversals. Diagnostics never repair or rewrite balances.

## Activation status

The drawer card and Today cash-flow cards are enabled from the reconciled
ledger source. Production activation still requires applying migrations in
order and reviewing reconciliation diagnostics for legacy data; this audit does
not fabricate historical account links or silently repair discrepancies.
