<# Staging-only stock adjustment positive/idempotency/negative-stock test. #>

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
  if ($response.Content) {
    return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  }
  try {
    $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  }
  catch { return $errorRecord | Out-String }
}

$stagingUrl = (Read-Required 'Staging project URL').TrimEnd('/')
$publishableKey = Read-Required 'Staging publishable key'
$email = Read-Required 'Authorized test-user email'
$password = Read-Host 'Authorized test-user password' -AsSecureString
$plainPassword = $null

try {
  $plainPassword = Convert-SecureString $password
  $auth = Invoke-RestMethod -Method Post -Uri "$stagingUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $publishableKey } -ContentType 'application/json' `
    -Body (@{ email = $email; password = $plainPassword } | ConvertTo-Json)
  if ([string]::IsNullOrWhiteSpace($auth.access_token)) { throw 'Authentication returned no access token.' }
  $headers = @{ apikey = $publishableKey; Authorization = "Bearer $($auth.access_token)" }

  $productResponse = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/products?branch_id=eq.22222222-2222-4222-8222-222222222222&name=like.SEC-17%20Product*&order=created_at.desc&limit=1&select=id,name" `
    -Headers $headers
  $product = @($productResponse)[0]
  if ($null -eq $product) { throw 'Expected the staged product-sync test product.' }
  $productId = $product.id

  $adjustmentId = [guid]::NewGuid().ToString()
  $adjustment = @{
    id = $adjustmentId
    branch_id = '22222222-2222-4222-8222-222222222222'
    product_id = $productId
    adjustment_type = 'stock_in'
    quantity = 3
    reason = 'SEC-17 staging idempotency test'
    reason_code = 'test_stock_in'
    reason_note = 'Synthetic test only'
    is_override = $false
  }
  $rpcUri = "$stagingUrl/rest/v1/rpc/adjust_inventory_stock_v2"
  try {
    $first = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' `
      -Body (@{ p_adjustment = $adjustment } | ConvertTo-Json -Depth 8)
  }
  catch {
    throw "Initial stock-in RPC failed: $(Get-HttpErrorDetail $_)"
  }
  $second = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' `
    -Body (@{ p_adjustment = $adjustment } | ConvertTo-Json -Depth 8)
  if ($first.duplicate -ne $false -or $second.duplicate -ne $true -or $first.quantity -ne $second.quantity) {
    throw 'Stock-in retry was not idempotent.'
  }

  $failedAdjustment = $adjustment.Clone()
  $failedAdjustment.id = [guid]::NewGuid().ToString()
  $failedAdjustment.adjustment_type = 'stock_out'
  $failedAdjustment.quantity = ([int]$first.quantity) + 1
  $failedAdjustment.reason_code = 'test_negative_stock'
  $wasRejected = $false
  try {
    Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' `
      -Body (@{ p_adjustment = $failedAdjustment } | ConvertTo-Json -Depth 8) | Out-Null
  }
  catch {
    $errorText = Get-HttpErrorDetail $_
    if ($errorText -notmatch '23514|below zero|Below zero') { throw "Unexpected stock-out failure: $errorText" }
    $wasRejected = $true
  }
  if (-not $wasRejected) { throw 'Negative stock-out unexpectedly succeeded.' }

  $inventory = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/inventory?product_id=eq.$productId&branch_id=eq.22222222-2222-4222-8222-222222222222&select=quantity" `
    -Headers $headers
  if (@($inventory).Count -ne 1 -or $inventory[0].quantity -ne $first.quantity) {
    throw 'Rejected negative stock-out changed inventory.'
  }

  [pscustomobject]@{
    result = 'PASS'
    product_id = $productId
    quantity_after_stock_in = $first.quantity
    retry_duplicate = $second.duplicate
    negative_stock_rejected = $wasRejected
    quantity_after_rejected_stock_out = $inventory[0].quantity
  } | ConvertTo-Json
}
finally { $plainPassword = $null }
