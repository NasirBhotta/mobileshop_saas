# NIZAAM delivery and customer features — implementation verification

Verified: 2026-10-30. The earlier implementation exists in the repository (commit `e4b886f` at verification). This report replaces the earlier pre-implementation proposal.

## Implemented behavior

1. **Repair delivery accounting:** new completion records the agreed charges without consuming parts, accruing supplier payables, or posting final profit. Delivery posts those effects atomically. Completed and Delivered remain distinct. Ticket locking and existing posting evidence protect retries and simultaneous delivery requests, including requests with different event IDs. Previously posted legacy Completed tickets are delivered without reposting.
2. **Repair customers:** select/search an existing customer, add one through the existing customer creation service, or continue as a manual/guest customer. Selecting a customer fills name/phone and links the actual ID. Repair sync reuses the existing customer resolver, pending parent creation, and persistent ID aliases. A database trigger validates customer/shop ownership.
3. **Customer history:** current-branch sales and repairs appear chronologically with references, product quantities/prices or repaired device, amounts, payments, balances, and receipt reprinting. Day, calendar week, month, custom, and all-time filters use paginated entries and whole-range totals. Original transaction IDs define visits; edits and payment rows do not add visits. Credit payment methods are excluded from money received; customer settlements are counted separately. Repair refunds reduce net repair receipts.

Existing sales account balances remain authoritative and tenant-wide. Repair balances are shown separately for the current branch. Sale entry balances are explicitly labelled as balances at checkout because the existing settlement model does not allocate each customer settlement to individual invoices. Offline history is labelled as cached and potentially incomplete; it does not claim this device has the customer's entire server history.

Existing receipt services, layouts, printer integration and entitlement checks are reused. Repair entries require an existing ticket reference. No historical invoices are manufactured. Existing account statements remain available; an additional date-filtered statement printer was not introduced.

## Files implementing the features

| Files | Reason |
| --- | --- |
| `lib/features/repairs/data/repositories/repair_repository.dart` | Versioned completion/delivery calls, dependency ordering, pending-cache protection, replay recovery, customer resolution |
| `lib/features/repairs/data/local/repair_financial_local_committer.dart` | Local completion preparation, transactional delivery posting, legacy protection, cancellation handling |
| `lib/features/repairs/data/models/repair_ticket_model.dart` | Persist accounting mode, charge inputs and finalization timestamp across cache/restart |
| `lib/features/repairs/domain/repair_accounting_contract.dart` | Preserve legacy contract and expose delivery accounting effects |
| `lib/features/repairs/presentation/providers/repair_provider.dart` | Refresh inventory and financial reports after delivery |
| `lib/features/repairs/presentation/screens/repair_form_screen.dart` | Existing/new/guest customer choices |
| `lib/features/pos/presentation/widgets/customer_attach_sheet.dart` | Optional customer result callback while preserving POS cart callers |
| `lib/core/local/local_database.dart`, `local_store.dart` | Additive local accounting flag, retained financial inputs, customer alias linkage for repairs |
| `lib/core/constants/app_strings.dart` | Explain delivery posting and label completion profit as expected |
| `lib/features/pos/data/models/customer_activity_model.dart` | Customer activity page and aggregate result |
| `lib/features/pos/data/local/customer_activity_local_store.dart` | Scoped, paginated offline history and full cached-range aggregates |
| `lib/features/pos/data/repositories/pos_repository.dart` | Authorized customer activity queries and existing receipt-document retrieval |
| `lib/features/pos/presentation/widgets/customer_activity_panel.dart`, `screens/customers_screen.dart` | Customer timeline, filters, analytics and reprint actions |
| `lib/features/reports/data/local/business_report_local_store.dart` | Final review correction: unposted Completed charges contribute zero revenue to status/technician breakdowns; completion counts remain unchanged |
| `supabase/migrations/20261028000100_repair_delivery_accounting.sql` | Versioned financial RPCs, safe cancellation, status guard, customer/shop validation |
| `supabase/migrations/20261028000200_customer_activity.sql` | Read-only history RPC, existing RLS/permission checks and scoped indexes |

Tests added/extended: `test/features/repairs/repair_financial_local_committer_test.dart`, `repair_accounting_contract_test.dart`, `repair_delivery_sync_integration_test.dart`, `test/features/pos/customer_activity_local_store_test.dart`, and `customer_attach_result_test.dart`. SQL assertions are in `supabase/tests/repair_delivery_customer_activity.sql`. `scripts/create_delivery_sql_fixture.py` and `scripts/test_delivery_sql_concurrency.py` support isolated database verification.

During this completion pass, `test/features/settings/staff_invitation_flow_test.dart` was made portable by normalizing CRLF before its existing multiline source assertion. The assertion and credential checks remain enabled; application invitation code was not changed. Nine temporary implementation-generator scripts from the earlier work were removed. The pre-existing `.brud/history/cleanup.json` modification was left untouched.

## Offline compatibility and data protection

- Existing mutation queue storage, serialized queue writes and snapshot merge behavior remain in place. Nothing clears local data, queue entries, or sync metadata.
- Existing v2 completion commands retain their historical meaning. New client actions use `prepare_repair_ticket_v3` and `deliver_repair_ticket_v3`.
- New offline commands persist their queue entry before their enclosing SQLite transaction commits. Replay can restore local effects if the queue survived an interrupted local commit.
- New commands do not overtake pending ticket parents or parts. Failed commands block dependent work for that ticket; permanent new-command conflicts retain needs-review metadata.
- Remote ticket refreshes preserve tickets with pending local mutations. Parent replay retains later local status rather than replacing it with the initial server state.
- Customer creation is insert-only during dependency recovery and uses the existing alias mechanism. Financial and inventory effects use existing immutable event identities and transactions.
- Cancellation of an unposted new Completed ticket does not restore unconsumed stock or reverse nonexistent profit. Existing posted tickets retain the refund and compensating-reversal workflow.
- No historical stock, profit, payment or invoice amounts were migrated or rewritten.

## Database rollout

**Both new SQL migrations must be applied to the intended backend before releasing this updated client.** They have only been applied to isolated local test databases during this work. No staging or production migration, deployment, commit or push was performed by the agent.

The server migration adds `delivery_accounting` with a legacy-compatible false default; the new completion RPC explicitly selects the deferred mode. Existing ticket modes and financial postings are not backfilled. SQLite adds the corresponding column using the existing add-column-if-missing mechanism. Older local records default to legacy behavior.

The rollout preserves older clients' v2 accounting semantics. New-client completion behavior uses the new commands. A strict simultaneous switch across every older installed client would require a separate client rollout policy.

## Executed verification and results

| Check | Actual result |
| --- | --- |
| Full Flutter suite, `flutter test --no-pub --reporter expanded` | **583 passed**, exit 0, before the final breakdown correction |
| Final repair/report suite after the breakdown correction | **71 passed**, exit 0; includes the added completion-versus-delivery report test |
| Previous affected repairs/POS/offline/printing suite | **187 passed**, recorded in `build/nizaam-affected-tests.log` |
| Dart analysis of application and new integration tests | Exit 0; four existing Radio API deprecation notices in the expense form, no errors or warnings |
| Both migrations and SQL assertions on a fresh isolated PostgreSQL database | Passed, exit 0 |
| Concurrent PostgreSQL delivery requests using different event IDs | Passed: stock deducted once and one financial event |
| Final release web build, `flutter build web --no-pub --no-wasm-dry-run` | Passed, exit 0; `build/web` generated |
| `git diff --check` | Passed |

The initial broad run's staff-invitation source-format assertion failed on Windows CRLF. After normalization of the test input, the complete suite passed. No test was disabled or skipped to obtain that result.

The new behavioral tests execute offline registered/guest ticket creation; persistence of financial inputs; deferred completion; local and server delivery idempotency; insufficient-stock rollback; legacy delivery; unposted cancellation; tenant rejection; interrupted HTTP sync followed by a new repository instance; queue-only crash recovery; permanent-conflict ordering; paginated analytics; date boundaries; customer selection/creation callbacks; and unchanged POS cart state. Existing tests cover receipt/PDF generation, printer connector failure handling, payments, refunds, inventory, reports, accounts and other modules.

Logs are retained under `build/nizaam-final-regression-tests.log`, `nizaam-final-repair-report-tests.log`, `nizaam-final-analysis.log`, `nizaam-final-sql-tests.log`, and `nizaam-final-web-build.log`.

## Verification limits and release checks

- No production or staging customer data was used. The SQL fixture uses permission test doubles and a reduced schema, so it does not prove live Supabase RLS, deployed triggers or schema drift compatibility.
- A new repository instance and persisted cache/queue replay were tested; a physical process kill, device reboot, or real device network toggle was not executed.
- Receipt generation and connector behavior were tested; no physical printer or interactive device acceptance session was executed.
- Existing remote business-report RPC definitions are not present in this repository. Their deployed all-branch behavior needs staging verification; the corrected local repair breakdowns and financial-event totals are tested.
- Before release, validate the two migrations against a staging copy with the real permissions and triggers, then exercise registered/new/guest customer creation, offline delivery/reconnect, cancellation/refund, historical reprints and old-client compatibility. Confirm that no production migration is run merely to test these flows.
