# SEC-17 client regression verification

Date: 2026-10-06. Scope: local Flutter verification only; no Supabase project was changed.

## Result

The secure-RPC compatibility updates compile and the selected regression suite passed.

| Check | Result |
| --- | --- |
| `flutter analyze` | No errors. Five pre-existing informational deprecations/unnecessary-import notices outside the SEC-17 files. |
| Inventory sync engine tests | Passed. |
| POS sale-return parent-recovery tests | Passed. |
| POS return/refund ledger tests | Passed. |
| Customer buy-in model and offline-cache repository tests | Passed. |

The combined targeted test command completed with **18 passing tests**.

## Meaning

The local compatibility routes still compile and their covered offline, retry, return-ledger and buy-in cache behavior is intact. This does not replace staging integration tests: the secure RPCs have not been installed in an isolated branch yet, and direct-write access has not been narrowed anywhere.

## Completed phase

This completes the local client regression-verification phase. The next phase requires the data-less Supabase staging branch described in `security_sec17_staging_runbook.md`.
