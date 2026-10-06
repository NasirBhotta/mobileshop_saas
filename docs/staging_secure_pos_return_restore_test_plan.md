# Staging test plan: POS return-parent recovery

The current direct restore route may upsert a sale and replace all items/payments. The staging RPC draft does not allow that. It accepts only a genuinely missing sale and delegates creation to `commit_pos_sale_v2`, so checkout validation, stock locking and ledger handling remain the authority.

## Required checks

1. A missing locally-created sale with the same authenticated `user_id`, active branch assignment, `pos.sale.return` and `pos.sale.create` permissions restores through the RPC, then a return sync succeeds.
2. A repeated request for the same sale id does not duplicate sale, stock or ledger records.
3. Existing sale, including an incomplete parent, is rejected for reconciliation; it is never overwritten or has children deleted by the RPC.
4. Different user, different branch, revoked assignment, disabled account, altered totals, altered payment amount and insufficient stock all fail without partial records.
5. A server with no RPC triggers the narrow client fallback; an installed RPC that rejects authorization/validation never falls back to direct writes.
6. Test cash, credit and split payment returns plus IMEI/unit sale snapshots with the real staging schema.

## Compatibility limitation to resolve before cutover

The secure draft preserves sale audit identity by requiring the original sale user to perform the recovery. If the product must support a different staff member recovering another user's offline sale, add a separate reviewed approval/reconciliation workflow. Do not weaken this RPC into a generic same-tenant financial table restore.
