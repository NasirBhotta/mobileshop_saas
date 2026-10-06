<# Staging-only authorization test for upsert_inventory_product_v2. #>

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
  if ($null -eq $rows) { return 0 }
  return @($rows).Count
}

$stagingUrl = (Read-Required 'Staging project URL').TrimEnd('/')
$publishableKey = Read-Required 'Staging publishable key'
$email = Read-Required 'Denied test-user email'
$password = Read-Host 'Denied test-user password' -AsSecureString
$plainPassword = $null

try {
  $plainPassword = Convert-SecureString $password
  $auth = Invoke-RestMethod -Method Post -Uri "$stagingUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $publishableKey } -ContentType 'application/json' `
    -Body (@{ email = $email; password = $plainPassword } | ConvertTo-Json)
  if ([string]::IsNullOrWhiteSpace($auth.access_token)) { throw 'Authentication returned no access token.' }

  $headers = @{ apikey = $publishableKey; Authorization = "Bearer $($auth.access_token)" }
  $productId = [guid]::NewGuid().ToString()
  $payload = @{
    id = $productId
    branch_id = '22222222-2222-4222-8222-222222222222'
    name = "SEC-17 Denied Product $productId"
    sale_price = 100
    cost_price = 50
    stock = 1
  }

  $wasRejected = $false
  try {
    Invoke-RestMethod -Method Post -Uri "$stagingUrl/rest/v1/rpc/upsert_inventory_product_v2" `
      -Headers $headers -ContentType 'application/json' `
      -Body (@{ p_product = $payload } | ConvertTo-Json -Depth 8) | Out-Null
  }
  catch {
    $errorText = $_ | Out-String
    if ($errorText -notmatch '42501|permission|Permission|forbidden|Forbidden') {
      throw "RPC failed for an unexpected reason: $errorText"
    }
    $wasRejected = $true
  }
  if (-not $wasRejected) { throw 'Unauthorized caller unexpectedly created a product.' }

  $productRows = Get-RowCount "$stagingUrl/rest/v1/products?id=eq.$productId&select=id" $headers
  $inventoryRows = Get-RowCount "$stagingUrl/rest/v1/inventory?product_id=eq.$productId&select=id" $headers
  if ($productRows -ne 0 -or $inventoryRows -ne 0) {
    throw "Rejected product request left partial state: products=$productRows inventory=$inventoryRows"
  }

  [pscustomobject]@{
    result = 'PASS'
    rejected = $true
    product_rows = $productRows
    inventory_rows = $inventoryRows
  } | ConvertTo-Json
}
finally { $plainPassword = $null }
