<#
One combined STAGING-only acceptance test for commit_pos_return_v2.
Creates synthetic sale/returns, checks cashier authorization, pending-to-approved,
exact retry, cash refund atomicity, and a credit refund. Credentials are prompted
locally and never written to disk.
#>
[CmdletBinding()]
param(
  [string] $InspectReturnId
)
$ErrorActionPreference = 'Stop'

function Read-Required([string] $prompt) {
  $value = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($value)) { throw "$prompt is required." }
  return $value.Trim()
}
function Convert-SecureString([securestring] $value) {
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
function Get-HttpErrorDetail($errorRecord) {
  if (-not [string]::IsNullOrWhiteSpace($errorRecord.ErrorDetails.Message)) { return $errorRecord.ErrorDetails.Message }
  $response = $errorRecord.Exception.Response
  if ($null -eq $response) { return $errorRecord | Out-String }
  try {
    $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  } catch { return $errorRecord | Out-String }
}
function Get-RestRows($response) {
  if ($null -eq $response) { return }
  # This PowerShell/runtime path represents JSON arrays as an object with
  # `value` and `Count` properties. Unwrap it before counting rows.
  if ($null -ne $response.PSObject.Properties['value']) { $response = $response.value }
  foreach ($row in $response) { if ($null -ne $row) { $row } }
}
function Sign-In([string] $url, [string] $key, [string] $email, [securestring] $password) {
  $plain = Convert-SecureString $password
  try {
    $auth = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" `
      -Headers @{ apikey = $key } -ContentType 'application/json' `
      -Body (@{ email = $email; password = $plain } | ConvertTo-Json)
    if (-not $auth.access_token -or -not $auth.user.id) { throw 'Authentication returned no user/session.' }
    return $auth
  } finally { $plain = $null }
}
function Invoke-Rpc([string] $url, [string] $name, $headers, $payload) {
  try {
    Invoke-RestMethod -Method Post -Uri "$url/rest/v1/rpc/$name" -Headers $headers `
      -ContentType 'application/json' -Body (@{ p_return = $payload } | ConvertTo-Json -Depth 12)
  } catch {
    throw "RPC $name failed: $(Get-HttpErrorDetail $_)"
  }
}
function New-Sale([string] $url, $headers, $product, [string] $userId, [string] $method, [string] $customerId) {
  $saleId = [guid]::NewGuid().ToString()
  $paymentId = [guid]::NewGuid().ToString()
  $ledgerId = if ($method -eq 'cash') { [guid]::NewGuid().ToString() } else { $null }
  $sale = @{
    id = $saleId; branch_id = '22222222-2222-4222-8222-222222222222'; user_id = $userId
    customer_id = $customerId; status = 'completed'; subtotal = 1000; discount_amount = 0
    tax_amount = 0; total = 1000; notes = 'SEC-17 synthetic return security test'
    created_at = [DateTime]::UtcNow.ToString('o')
    sale_items = @(@{ product_id = $product.id; product_name = $product.name; product_sku = $product.sku
      quantity = 1; unit_price = 1000; unit_cost_at_sale = [decimal]$product.cost_price
      discount_amount = 0; tax_rate = 0; cogs_total = [decimal]$product.cost_price; line_total = 1000 })
    sale_payments = @(@{ id = $paymentId; method = $method; amount = 1000
      account_id = if ($method -eq 'cash') { '33333333-3333-4333-8333-333333333333' } else { $null }
      ledger_transaction_id = $ledgerId })
  }
  try { $committed = Invoke-RestMethod -Method Post -Uri "$url/rest/v1/rpc/commit_pos_sale_v2" -Headers $headers `
      -ContentType 'application/json' -Body (@{ p_sale = $sale } | ConvertTo-Json -Depth 10) }
  catch { throw "Synthetic $method sale setup failed: $(Get-HttpErrorDetail $_)" }
  if ($committed -ne $true) { throw "Synthetic $method sale was not newly committed." }
  return @{ sale_id = $saleId; payment_id = $paymentId }
}
function New-ReturnPayload($sale, $userId, [string] $method, [string] $paymentId, [bool] $approved, [string] $approverId) {
  $returnId = [guid]::NewGuid().ToString()
  $restockId = [guid]::NewGuid().ToString()
  $payload = @{
    id = $returnId; original_sale_id = $sale.sale_id; branch_id = '22222222-2222-4222-8222-222222222222'
    user_id = $userId; status = if ($approved) { 'approved' } else { 'pending_approval' }
    refund_method = $method; refund_amount = 1000; refund_payment_id = $paymentId
    approval_required_reason = if ($approved) { $null } else { 'SEC-17 test pending approval' }
    override_reason = $null; approved_by = if ($approved) { $approverId } else { $null }
    created_at = [DateTime]::UtcNow.ToString('o')
    items = @(@{ product_id = $script:product.id; product_name = $script:product.name
      product_sku = $script:product.sku; quantity = 1; refund_amount = 1000
      restock_product_id = $restockId; restock_condition = 'returned'; resale_price = 1000 })
    refund_legs = @()
  }
  if ($method -eq 'cash') {
    $payload.refund_legs = @(@{ id = [guid]::NewGuid().ToString(); original_payment_id = $paymentId
      account_id = '33333333-3333-4333-8333-333333333333'; amount = 1000
      ledger_transaction_id = [guid]::NewGuid().ToString() })
  }
  return $payload
}

$stagingUrl = 'https://diqwalqgfkusqefomtdl.supabase.co'
if ($stagingUrl -notmatch '^https://') { throw 'Use the HTTPS staging project URL.' }
$publishableKey = 'sb_publishable_emcHfOzD9niE_vCyNPmNuw_rAMbJGQI'
$ownerEmail = 'sec17.staging.owner@gmail.com'
$cashierEmail = 'sec17.denied@gmail.com'
$testUserPassword = Read-Host 'Shared staging test-user password (used for both accounts)' -AsSecureString
$ownerAuth = $cashierAuth = $null
try {
  $ownerAuth = Sign-In $stagingUrl $publishableKey $ownerEmail $testUserPassword
  $cashierAuth = Sign-In $stagingUrl $publishableKey $cashierEmail $testUserPassword
  $ownerHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($ownerAuth.access_token)" }
  $cashierHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($cashierAuth.access_token)" }
  if (-not [string]::IsNullOrWhiteSpace($InspectReturnId)) {
    $returnRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
      "$stagingUrl/rest/v1/sale_returns?id=eq.$InspectReturnId&select=id,status" -Headers $ownerHeaders))
    $itemRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
      "$stagingUrl/rest/v1/sale_return_items?return_id=eq.$InspectReturnId&select=restock_product_id" -Headers $ownerHeaders))
    $productRows = @(
      foreach ($itemRow in $itemRows) {
        Get-RestRows (Invoke-RestMethod -Method Get -Uri `
          "$stagingUrl/rest/v1/products?id=eq.$($itemRow.restock_product_id)&select=id" -Headers $ownerHeaders)
      }
    )
    $refundRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
      "$stagingUrl/rest/v1/sale_return_refund_legs?return_id=eq.$InspectReturnId&select=id,return_id" -Headers $ownerHeaders))
    [pscustomobject]@{
      return_query = $returnRows
      item_query = $itemRows
      product_query = $productRows
      refund_leg_query = $refundRows
    } | ConvertTo-Json -Depth 8
    return
  }
  $branchId = '22222222-2222-4222-8222-222222222222'
  $productRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/products?branch_id=eq.$branchId&name=like.SEC-17%20Product*&order=created_at.desc&limit=1&select=id,name,sku,cost_price" `
    -Headers $ownerHeaders))
  $script:product = $productRows[0]
  if ($null -eq $script:product) { throw 'Expected the staging SEC-17 product-sync test product.' }
  $sourceInventoryRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/inventory?branch_id=eq.$branchId&product_id=eq.$($script:product.id)&select=quantity" -Headers $ownerHeaders))
  $sourceInventory = $sourceInventoryRows[0]
  if ($null -eq $sourceInventory -or [int]$sourceInventory.quantity -lt 2) { throw 'Test product requires at least two stock units.' }

  # Cash scenario: owner creates a pending return; the unauthorized test account
  # cannot approve it; owner approves;
  # exact retry must not create a second returned product, refund, or ledger row.
  $cashSale = New-Sale $stagingUrl $ownerHeaders $script:product $ownerAuth.user.id 'cash' $null
  $pending = New-ReturnPayload $cashSale $ownerAuth.user.id 'cash' $cashSale.payment_id $false $null
  $pendingResult = Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $pending
  $pendingRetry = Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $pending
  if ($pendingResult.status -ne 'pending_approval' -or $pendingRetry.duplicate -ne $true) { throw 'Pending return creation/retry did not behave as expected.' }

  $unauthorized = $pending.Clone(); $unauthorized.status = 'approved'; $unauthorized.approved_by = $cashierAuth.user.id
  $denied = $false
  try { Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $cashierHeaders $unauthorized | Out-Null }
  catch { $detail = Get-HttpErrorDetail $_; if ($detail -notmatch '42501|permission|required') { throw "Unexpected unauthorized approval rejection: $detail" }; $denied = $true }
  if (-not $denied) { throw 'Unauthorized test account unexpectedly approved a return.' }
  $afterDeniedRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/sale_returns?id=eq.$($pending.id)&select=status" -Headers $ownerHeaders))
  $afterDenied = $afterDeniedRows[0]
  if ($afterDenied.status -ne 'pending_approval') { throw 'Denied approval changed the pending return state.' }

  $invalidRefund = $pending.Clone(); $invalidRefund.status = 'approved'; $invalidRefund.approved_by = $ownerAuth.user.id
  $invalidRefund.refund_legs = @($pending.refund_legs | ForEach-Object {
    $leg = $_.Clone(); $leg.account_id = [guid]::NewGuid().ToString(); $leg
  })
  $refundRejected = $false
  try { Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $invalidRefund | Out-Null }
  catch { $detail = Get-HttpErrorDetail $_; if ($detail -notmatch '22023|invalid original payment account') { throw "Unexpected invalid refund rejection: $detail" }; $refundRejected = $true }
  if (-not $refundRejected) { throw 'Invalid cash refund allocation unexpectedly succeeded.' }
  $rollbackReturnRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/sale_returns?id=eq.$($pending.id)&select=status" -Headers $ownerHeaders))
  $rollbackReturn = $rollbackReturnRows[0]
  $rollbackProduct = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/products?id=eq.$($pending['items'][0]['restock_product_id'])&select=id" -Headers $ownerHeaders))
  $rollbackLegs = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/sale_return_refund_legs?return_id=eq.$($pending.id)&select=id" -Headers $ownerHeaders))
  if ($rollbackReturn.status -ne 'pending_approval' -or $rollbackProduct.Count -ne 0 -or $rollbackLegs.Count -ne 0) {
    throw "Rollback verification mismatch: return_id=$($pending.id), restock_product_id=$($pending['items'][0]['restock_product_id']), return_status='$($rollbackReturn.status)', product_rows=$($rollbackProduct.Count), refund_leg_rows=$($rollbackLegs.Count). Compare with the staging SQL read-only verification before concluding there was a partial write."
  }

  $approved = $pending.Clone(); $approved.status = 'approved'; $approved.approved_by = $ownerAuth.user.id
  $approvedResult = Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $approved
  $approvedRetry = Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $approved
  if ($approvedResult.status -ne 'approved' -or $approvedRetry.duplicate -ne $true) { throw 'Cash return approval/retry failed.' }
  $restockId = $approved['items'][0]['restock_product_id']
  $cashStockRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/inventory?branch_id=eq.$branchId&product_id=eq.$restockId&select=quantity" -Headers $ownerHeaders))
  $cashStock = $cashStockRows[0]
  $cashLegs = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/sale_return_refund_legs?return_id=eq.$($pending.id)&select=id" -Headers $ownerHeaders))
  if ($null -eq $cashStock -or [int]$cashStock.quantity -ne 1 -or $cashLegs.Count -ne 1) { throw 'Cash approval did not create exactly one restock and refund leg.' }

  # Credit scenario: create a synthetic customer and credit sale, then verify that
  # the atomic return reverses receivable and restocks exactly once.
  $customerResponse = Invoke-RestMethod -Method Post -Uri "$stagingUrl/rest/v1/customers" -Headers ($ownerHeaders + @{ Prefer = 'return=representation' }) `
    -ContentType 'application/json' -Body (@{ tenant_id = '11111111-1111-4111-8111-111111111111'; branch_id = $branchId
      full_name = 'SEC-17 Synthetic Return Customer'; phone = ('SEC17' + [guid]::NewGuid().ToString('N').Substring(0,12)) } | ConvertTo-Json)
  $customerRows = @(Get-RestRows $customerResponse)
  $customer = $customerRows[0]
  if ($null -eq $customer -or -not $customer.id) { throw 'Could not create the synthetic staging credit customer.' }
  $creditSale = New-Sale $stagingUrl $ownerHeaders $script:product $ownerAuth.user.id 'credit' $customer.id
  $creditReturn = New-ReturnPayload $creditSale $ownerAuth.user.id 'credit' $null $true $ownerAuth.user.id
  $creditResult = Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $creditReturn
  $creditRetry = Invoke-Rpc $stagingUrl 'commit_pos_return_v2' $ownerHeaders $creditReturn
  if ($creditResult.status -ne 'approved' -or $creditRetry.duplicate -ne $true) { throw 'Credit return approval/retry failed.' }
  $creditAdjustmentRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/sale_return_credit_adjustments?return_id=eq.$($creditReturn.id)&select=id,amount" -Headers $ownerHeaders))
  $creditAdjustment = $creditAdjustmentRows[0]
  $creditStockRows = @(Get-RestRows (Invoke-RestMethod -Method Get -Uri `
    "$stagingUrl/rest/v1/inventory?branch_id=eq.$branchId&product_id=eq.$($creditReturn['items'][0]['restock_product_id'])&select=quantity" -Headers $ownerHeaders))
  $creditStock = $creditStockRows[0]
  if ($null -eq $creditAdjustment -or [decimal]$creditAdjustment.amount -ne 1000 -or $null -eq $creditStock -or [int]$creditStock.quantity -ne 1) {
    throw 'Credit return did not create exactly one receivable adjustment and restock.'
  }

  [pscustomobject]@{
    result = 'PASS'
    owner_pending_create = $true
    unauthorized_approval_denied_without_state_change = $denied
    invalid_refund_rolled_back = $refundRejected
    owner_cash_approval_and_retry = $true
    cash_refund_legs = $cashLegs.Count
    cash_restock_quantity = $cashStock.quantity
    credit_approval_and_retry = $true
    credit_adjustment_amount = $creditAdjustment.amount
    credit_restock_quantity = $creditStock.quantity
  } | ConvertTo-Json
}
finally {
  $testUserPassword = $null; $ownerAuth = $cashierAuth = $null
}
