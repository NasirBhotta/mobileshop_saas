<#
Runs a staging-only negative authorization test for commit_customer_buyin_v2.
The test must be rejected before it creates a product, IMEI unit or purchase.
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

function Get-RowCount([string] $uri, [hashtable] $headers) {
  $rows = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
  return @($rows).Count
}

$stagingUrl = (Read-Required 'Staging project URL').TrimEnd('/')
$publishableKey = Read-Required 'Staging publishable key'
$email = Read-Required 'Denied test-user email'
$password = Read-Host 'Denied test-user password' -AsSecureString
$plainPassword = $null

try {
  $plainPassword = Convert-SecureString $password
  $auth = Invoke-RestMethod -Method Post `
    -Uri "$stagingUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $publishableKey } `
    -ContentType 'application/json' `
    -Body (@{ email = $email; password = $plainPassword } | ConvertTo-Json)
  if ([string]::IsNullOrWhiteSpace($auth.access_token)) { throw 'Authentication returned no access token.' }

  $requestId = [guid]::NewGuid().ToString()
  $productId = [guid]::NewGuid().ToString()
  $unitId = [guid]::NewGuid().ToString()
  $imei = ('DENIED' + (Get-Date -Format 'yyyyMMddHHmmss') + (Get-Random -Minimum 100 -Maximum 999))
  $headers = @{ apikey = $publishableKey; Authorization = "Bearer $($auth.access_token)" }
  $payload = @{
    id = $requestId
    branch_id = '22222222-2222-4222-8222-222222222222'
    product_id = $productId
    inventory_unit_id = $unitId
    create_product = $true
    product_name = "SEC-17 Denied Buy-in $requestId"
    imei1 = $imei
    seller_name = 'SEC-17 Synthetic Seller'
    seller_cnic = '00000-0000000-0'
    seller_phone = '03000000000'
    purchase_price = 1000
    expected_sale_price = 1500
    declaration_agreed = $true
  }

  $wasRejected = $false
  try {
    Invoke-RestMethod -Method Post `
      -Uri "$stagingUrl/rest/v1/rpc/commit_customer_buyin_v2" `
      -Headers $headers -ContentType 'application/json' `
      -Body (@{ p_buyin = $payload } | ConvertTo-Json -Depth 8) | Out-Null
  }
  catch {
    $errorText = $_ | Out-String
    if ($errorText -notmatch '42501|permission|Permission|forbidden|Forbidden') {
      throw "RPC failed for an unexpected reason: $errorText"
    }
    $wasRejected = $true
  }
  if (-not $wasRejected) { throw 'Unauthorized caller unexpectedly completed the RPC.' }

  $productRows = Get-RowCount "$stagingUrl/rest/v1/products?id=eq.$productId&select=id" $headers
  $unitRows = Get-RowCount "$stagingUrl/rest/v1/inventory_units?id=eq.$unitId&select=id" $headers
  $purchaseRows = Get-RowCount "$stagingUrl/rest/v1/customer_purchases?id=eq.$requestId&select=id" $headers
  if ($productRows -ne 0 -or $unitRows -ne 0 -or $purchaseRows -ne 0) {
    throw "Rejected request left partial state: products=$productRows units=$unitRows purchases=$purchaseRows"
  }

  [pscustomobject]@{
    result = 'PASS'
    rejected = $true
    product_rows = $productRows
    inventory_unit_rows = $unitRows
    purchase_rows = $purchaseRows
  } | ConvertTo-Json
}
finally {
  $plainPassword = $null
}
