# Staging test plan: customer buy-in RPC

Run only after `staging_secure_customer_buyin_draft.sql` is reviewed and applied to a separate staging project.

1. New product buy-in creates one product, inventory row, available IMEI unit and purchase record; optional account balance decreases once.
2. Existing-product buy-in increments inventory by one, never writes a client-supplied absolute quantity, and does not overwrite the existing product's tenant or branch.
3. Exact retry with the same purchase ID returns `duplicate: true`, without a second unit, stock increment or account transaction.
4. Same purchase ID with another product/IMEI fails. Duplicate `(branch_id, imei)` fails with no inventory or account side effect.
5. Wrong tenant/branch, inactive/deleted/revoked user, missing product/IMEI permission and missing account-transaction permission all fail before mutation.
6. Cross-branch/inactive/insufficient payment account fails with no purchase, product, unit or inventory partial state.
7. Existing client remains on its legacy flow until its compatibility update is released. The draft intentionally does not revoke direct writes.
