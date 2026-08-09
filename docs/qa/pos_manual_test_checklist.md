# POS manual test checklist

Run this checklist after POS database migrations are deployed and before every
POS release. Record the device, app build, user role, branch, network state,
and result for each run.

## Checkout

- Complete a cash sale and verify receipt, stock, sale history, cash account,
  and account ledger all change exactly once.
- Complete a split-payment sale and verify each payment reaches its selected
  compatible account.
- Complete a credit sale and verify the customer outstanding balance changes
  exactly once.
- For a `Rs60 = Rs50 account payment + Rs10 credit` sale, return the full item:
  verify cash refund max is Rs50, Khata adjustment max is Rs10, and the chosen
  original payment account decreases by the cash refund exactly once.
- Double-tap checkout and retry after a timeout; verify only one sale, stock
  deduction, customer adjustment, and ledger posting exist.
- Attempt checkout with stale stock from two devices; verify one succeeds and
  the other receives an insufficient-stock error without partial writes.
- Edit an item price through the existing UI and verify calculated subtotal,
  discount, tax, payment total, receipt, and stored sale remain aligned.

## Discounts and permissions

- Apply a discount inside the cashier limit without a manager PIN.
- Apply a discount above the cashier limit with an invalid PIN; verify denial.
- Apply it with an authorized manager/owner PIN; verify approval and audit log.
- Try a valid PIN belonging to another tenant or an inactive user; verify denial.
- Verify users without `pos.sale.create` cannot commit a sale through the UI or
  by calling the RPC directly.

## Offline and recovery

- Complete an offline sale, restart the app, reconnect, and verify it syncs once.
- Create an offline credit sale for an offline-created customer and verify
  customer reconciliation does not duplicate the customer or balance.
- Hold and resume a cart offline, then reconnect and verify cart state remains
  correct.

## Returns

- Process full and partial cash returns and verify stock, refund account, and
  ledger values.
- When a sale has multiple non-credit payment accounts, select each eligible
  refund account and verify its remaining refundable capacity is displayed.
- Process a credit return and verify receivable decreases without cash movement.
- Retry/approve the same return twice and verify no duplicate restock or refund.
- Attempt to return more than the sold/remaining quantity and verify rejection.
- Verify pending-return approval permissions and return-window override rules.

## Performance and UX

- Search products by name, SKU, barcode, and IMEI with a large catalog.
- Confirm checkout shows a single loading state and remains protected from
  duplicate taps.
- Confirm network/offline, permission, stock, payment-account, and validation
  errors are understandable and leave the cart recoverable.
