<#
Staging-only test for public.restore_pos_sale_for_return.
It creates one synthetic sale through the secure recovery boundary, proves that
an exact repeat cannot overwrite it, and proves the denied user cannot create
one. It never contacts production and prompts for credentials without writing
them to disk.
#>

[CmdletBinding()]
param()

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
  if (-not [string]::IsNullOrWhiteSpace($errorRecord.ErrorDetails.Message)) {
    return $errorRecord.ErrorDetails.Message
  }
  $response = $errorRecord.Exception.Response
  if ($null -eq $response) { return $errorRecord | Out-String }
  try {
    $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  }
  catch { return $errorRecord | Out-String }
}

function Sign-In($url, $key, $email, [securestring] $password) {
  $plain = Convert-SecureString $password
  try {
    $auth = Invoke-RestMethod -Method Post -Uri "$url/auth/v1/token?grant_type=password" `
      -Headers @{ apikey = $key } -ContentType 'application/json' `
      -Body (@{ email = $email; password = $plain } | ConvertTo-Json)
    if ([string]::IsNullOrWhiteSpace($auth.access_token) -or [string]::IsNullOrWhiteSpace($auth.user.id)) {
      throw 'Authentication returned no authenticated user.'
    }
    return $auth
  }
  finally { $plain = $null }
}

$stagingUrl = (Read-Required 'Staging project URL').TrimEnd('/')
if ($stagingUrl -notmatch '^https://') { throw 'Use the HTTPS staging project URL.' }
$publishableKey = Read-Required 'Staging publishable key'
$ownerEmail = Read-Required 'Authorized owner email'
$ownerPassword = Read-Host 'Authorized owner password' -AsSecureString
$deniedEmail = Read-Required 'Denied test-user email'
$deniedPassword = Read-Host 'Denied test-user password' -AsSecureString

try {
  $ownerAuth = Sign-In $stagingUrl $publishableKey $ownerEmail $ownerPassword
  $deniedAuth = Sign-In $stagingUrl $publishableKey $deniedEmail $deniedPassword
  $ownerHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($ownerAuth.access_token)" }
  $deniedHeaders = @{ apikey = $publishableKey; Authorization = "Bearer $($deniedAuth.access_token)" }
  $branchId = '22222222-2222-4222-8222-222222222222'
  $accountId = '33333333-3333-4333-8333-333333333333'

  $productResponse = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/products?branch_id=eq.$branchId&name=like.SEC-17%20Product*&order=created_at.desc&limit=1&select=id,name,sku,cost_price" `
    -Headers $ownerHeaders
  $product = @($productResponse)[0]
  if ($null -eq $product) { throw 'Expected the staged product-sync test product.' }

  $inventoryBefore = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/inventory?branch_id=eq.$branchId&product_id=eq.$($product.id)&select=quantity" `
    -Headers $ownerHeaders
  if (@($inventoryBefore).Count -ne 1 -or [int]$inventoryBefore[0].quantity -lt 1) {
    throw 'The staged test product needs at least one unit of stock.'
  }

  $saleId = [guid]::NewGuid().ToString()
  $paymentId = [guid]::NewGuid().ToString()
  $ledgerId = [guid]::NewGuid().ToString()
  $sale = @{
    id = $saleId
    branch_id = $branchId
    user_id = $ownerAuth.user.id
    status = 'completed'
    subtotal = 1000
    discount_amount = 0
    tax_amount = 0
    total = 1000
    notes = 'SEC-17 synthetic return-parent recovery test'
    sale_items = @(@{
      product_id = $product.id
      product_name = $product.name
      product_sku = $product.sku
      quantity = 1
      unit_price = 1000
      unit_cost_at_sale = $product.cost_price
      discount_amount = 0
      tax_rate = 0
      cogs_total = $product.cost_price
      line_total = 1000
    })
    sale_payments = @(@{
      id = $paymentId
      method = 'cash'
      amount = 1000
      account_id = $accountId
      ledger_transaction_id = $ledgerId
    })
  }
  $rpcUri = "$stagingUrl/rest/v1/rpc/restore_pos_sale_for_return"
  $body = @{ p_sale = $sale } | ConvertTo-Json -Depth 8
  $created = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $ownerHeaders `
    -ContentType 'application/json' -Body $body
  if ($created -ne $true) { throw 'Initial secure sale recovery did not create the sale.' }

  $repeatRejected = $false
  try {
    Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $ownerHeaders `
      -ContentType 'application/json' -Body $body | Out-Null
  }
  catch {
    $detail = Get-HttpErrorDetail $_
    if ($detail -notmatch '23505|already exists|already used') { throw "Unexpected repeat failure: $detail" }
    $repeatRejected = $true
  }
  if (-not $repeatRejected) { throw 'Repeated recovery unexpectedly succeeded.' }

  $inventoryAfterRepeat = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/inventory?branch_id=eq.$branchId&product_id=eq.$($product.id)&select=quantity" `
    -Headers $ownerHeaders
  $sales = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/sales?id=eq.$saleId&select=id,sale_items(id),sale_payments(id)" `
    -Headers $ownerHeaders
  if (@($sales).Count -ne 1 -or @($sales[0].sale_items).Count -ne 1 -or @($sales[0].sale_payments).Count -ne 1) {
    throw 'Recovered sale does not have exactly one parent, item, and payment.'
  }
  if ([int]$inventoryAfterRepeat[0].quantity -ne ([int]$inventoryBefore[0].quantity - 1)) {
    throw 'Repeat recovery changed inventory.'
  }

  $deniedSale = $sale.Clone()
  $deniedSale.id = [guid]::NewGuid().ToString()
  $deniedSale.user_id = $deniedAuth.user.id
  $deniedSale.sale_payments = @(@{
    id = [guid]::NewGuid().ToString(); method = 'cash'; amount = 1000
    account_id = $accountId; ledger_transaction_id = [guid]::NewGuid().ToString()
  })
  $deniedRejected = $false
  try {
    Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $deniedHeaders -ContentType 'application/json' `
      -Body (@{ p_sale = $deniedSale } | ConvertTo-Json -Depth 8) | Out-Null
  }
  catch {
    $detail = Get-HttpErrorDetail $_
    if ($detail -notmatch '42501|permission|required') { throw "Unexpected denied-user failure: $detail" }
    $deniedRejected = $true
  }
  if (-not $deniedRejected) { throw 'Denied user unexpectedly restored a sale.' }

  [pscustomobject]@{
    result = 'PASS'
    sale_id = $saleId
    product_id = $product.id
    recovered_sale_created = $created
    repeat_rejected_without_overwrite = $repeatRejected
    denied_user_rejected = $deniedRejected
    quantity_before = $inventoryBefore[0].quantity
    quantity_after = $inventoryAfterRepeat[0].quantity
  } | ConvertTo-Json
}
finally {
  $ownerPassword = $null
  $deniedPassword = $null
}
