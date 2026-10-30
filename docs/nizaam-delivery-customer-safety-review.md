# Delivery accounting and customer features: safety review

Date: 2026-10-28. Status: pre-implementation; no application or database changes.

The requested three features are not implemented. This review records a concrete
compatibility conflict for resolution before changing financial behavior, as
required by the production-data protection instructions.

## Findings from the repository

- `lib/features/repairs/data/repositories/repair_repository.dart` calls
  `complete_repair_ticket_v2`, mirrors its effects locally, and persists the same
  command for offline replay. Delivery currently uses a direct ticket update.
  Replay has single-flight protection, per-ticket financial failure ordering,
  equivalence checks, and a needs-review state. Preserve these protections.
- `lib/features/repairs/data/local/repair_financial_local_committer.dart` consumes
  planned parts, deducts inventory, accrues supplier payables, inserts an immutable
  completion event, and sets finalized_at in one local transaction. Cancellation
  treats Completed and Delivered as financially finalized.
- `supabase/migrations/20260728001500_repair_hybrid_financial_engine.sql` defines
  the matching completion RPC. It locks the ticket and uses an event source key
  for idempotency. These are existing financial contracts, not just UI labels.
- `supabase/migrations/20260729000200_atomic_paid_repair_cancellation.sql` requires
  a completion snapshot when cancelling Completed or Delivered tickets.
  `20260802000100_repair_effective_accounting_date.sql` preserves accounting dates
  for reversals. Both paths need coordinated handling of unposted Completed tickets.
- `lib/core/local/local_database.dart` manages SQLite tables and additive column
  upgrades. `lib/core/local/local_store.dart` stores customer aliases, repair
  tickets, parts and financial records.
- `lib/core/offline/offline_store.dart` persists the user mutation queue in
  SharedPreferences, serializes queue writes, and merges sync results with the
  latest queue to preserve operations enqueued during sync. It also maintains
  fallback caches. No queue clearing or replacement is proposed.
- `lib/features/repairs/presentation/providers/repair_provider.dart` invokes
  repository sync and refreshes local caches. Repository fetch also starts sync.
- Repair tickets already have an optional customer ID. The creation form currently
  exposes manual name and phone. Its sync upsert does not resolve customer aliases
  or establish an unsynchronized customer parent first.
- `lib/features/pos/data/repositories/sale_customer_resolver.dart` already handles
  that dependency for sales, including pending customer creation and race recovery.
  Reuse this mechanism for repair linking with existing tenant/branch validation.
- `lib/features/pos/presentation/widgets/customer_attach_sheet.dart` provides
  existing customer search/add UI, but attaches to POS state; adapting its result
  contract must preserve existing POS callers.
- Customer history is in POS: `customers_screen.dart`, `pos_repository.dart`, and
  `customer_dashboard_model.dart`. The model includes sales, settlements and manual
  ledger entries; its repair field is a count. Customer sales fetch is capped at
  100. The authoritative outstanding balance deliberately is not reconstructed
  from that limited history. Preserve that distinction.

## Concrete conflict

An older client can have a queued completion whose stock, supplier and profit
effects are already committed locally. Reinterpreting its existing v2 command
as an unposted completion makes server and client disagree. Keeping v2 unchanged
allows older clients to continue posting at Completed. A global immediate
Delivered-only rule and uninterrupted old-client financial semantics therefore
cannot both be promised without an explicit compatibility rollout.

Status alone also cannot distinguish legacy posted Completed tickets from new
unposted Completed tickets. Applying delivery deductions to both would double-post
legacy stock and profit. Cancelling the latter with current code can fail because
its required completion snapshot does not exist.

## Proposed backward-compatible implementation

1. Preserve existing v2 RPC and queued payload semantics. Add a versioned completion
   command that records the agreed charge/cost inputs without inventory or final
   profit effects, plus a versioned delivery command that posts them atomically.
   Keep Completed and Delivered distinct. Reject unsafe generic status writes for
   the new accounting mode on the server as well as in the app.
2. Use additive, server-controlled accounting-mode metadata on tickets so old
   clients default to the legacy path and new commands explicitly select the new
   path. Do not infer mode from status or rewrite existing financial history.
   Validate ambiguous existing data in a read-only audit before any backfill.
3. In delivery, lock the ticket and relevant stock rows, check existing immutable
   posting identity for the ticket, and return the existing result on retries,
   including retries using a different request ID. Legacy posted tickets only get
   delivery state/log updates. Preserve existing report event contracts where
   possible; delivery posting time supplies the new event's accounting date.
4. Mirror versioned semantics locally, including charge inputs across app restarts.
   Keep existing queue types and metadata intact; add command types to the current
   dispatcher and per-ticket ordering guards. Reconcile interrupted requests by
   identity and content; retain mismatches for review. Never clear pending work.
5. Cancellation must use actual posting evidence and accounting mode. Unposted
   completion has no stock/profit reversal; posted legacy/new tickets retain the
   existing explicit refund and compensating-reversal rules. Do not silently
   reverse history on reopening or ordinary edits.
6. Add repair customer selection and creation using existing customer services,
   validation and permissions. Resolve aliases and synchronize the customer parent
   before the repair mutation. Preserve guest entry and historical text snapshots.
7. Extend customer history with authorized, paginated sales/repair queries and
   separate whole-range aggregates. Define a visit by originating transaction ID;
   related invoice/payment rows do not add visits. Include authoritative payments,
   refunds, settlements and ledger adjustments without counting the same payment
   twice. Preserve authoritative balance semantics and distinguish period activity
   from current balance. Use additive scoped indexes after checking existing ones.
8. Reuse existing sales and repair receipt services for real documents only, with
   existing print permissions. Keep account statements distinct from invoices.

Rollout decision required: accept legacy completion semantics for older clients
and their pending operations during a versioned transition, or require clients to
upgrade and reconcile pending work before activating the new rule. The former is
recommended to preserve offline availability. No production activation is implied.

## Verification scope

Baseline automated tests passed: **95 tests, exit code 0** (approximately 70 seconds).
Executed command:

```powershell
flutter test test/features/repairs test/core/offline/offline_mutation_queue_test.dart test/features/pos/data/repositories/sale_customer_resolver_test.dart test/features/pos/receipt_service_test.dart test/features/pos/receipt_layout_regression_test.dart test/features/printing/escpos_receipt_test.dart --reporter compact
```

Coverage includes repairs, the offline queue, customer resolution, receipt
service/layout, and ESC/POS receipt generation. These include
source-contract tests as well as executable behavior tests; passing them does not
demonstrate a live server or printer workflow.

No database migration has been applied. No production/staging data, live network
reconnection, physical printer, or interactive customer workflow has been tested.
No implementation build or new-feature verification has been performed.

Required acceptance coverage after implementation: old/new command compatibility;
legacy Completed delivery without reposting; concurrent delivery with different
request IDs; interrupted sync and restart; insufficient stock rollback; failed
parent customer sync; duplicate-phone alias recovery; guest and linked tickets;
tenant/branch permissions; cancellation/refund accounting; date-filtered full-range
analytics with pagination; real historical receipt reprints; existing customer CRUD,
POS, inventory, reports and billing regression tests. Run SQL integration tests on
an isolated migrated database, never by exercising production business records.
