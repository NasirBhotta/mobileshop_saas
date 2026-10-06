<#
Runs an authenticated, staging-only positive/idempotency test for
public.commit_customer_buyin_v2. It does not contact production.

Inputs are prompted and never written to disk. Do not paste credentials in chat.
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

$stagingUrl = (Read-Required 'Staging project URL').TrimEnd('/')
if ($stagingUrl -notmatch '^https://') { throw 'Use the HTTPS staging project URL.' }
$publishableKey = Read-Required 'Staging publishable key'
$email = Read-Required 'Staging test-user email'
$password = Read-Host 'Staging test-user password' -AsSecureString
$plainPassword = $null

try {
  $plainPassword = Convert-SecureString $password
  $authBody = @{ email = $email; password = $plainPassword } | ConvertTo-Json
  $auth = Invoke-RestMethod `
    -Method Post `
    -Uri "$stagingUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $publishableKey } `
    -ContentType 'application/json' `
    -Body $authBody

  if ([string]::IsNullOrWhiteSpace($auth.access_token)) {
    throw 'Staging authentication returned no access token.'
  }

  $requestId = [guid]::NewGuid().ToString()
  $productId = [guid]::NewGuid().ToString()
  $unitId = [guid]::NewGuid().ToString()
  $imei = ('SEC17' + (Get-Date -Format 'yyyyMMddHHmmss') + (Get-Random -Minimum 100 -Maximum 999))
  $payload = @{
    id = $requestId
    branch_id = '22222222-2222-4222-8222-222222222222'
    product_id = $productId
    inventory_unit_id = $unitId
    create_product = $true
    product_name = "SEC-17 Staging Buy-in $requestId"
    imei1 = $imei
    seller_name = 'SEC-17 Synthetic Seller'
    seller_cnic = '00000-0000000-0'
    seller_phone = '03000000000'
    purchase_price = 12000
    expected_sale_price = 15000
    payment_account_id = '33333333-3333-4333-8333-333333333333'
    payment_method = 'cash'
    declaration_agreed = $true
  }
  $headers = @{ apikey = $publishableKey; Authorization = "Bearer $($auth.access_token)" }
  $rpcUri = "$stagingUrl/rest/v1/rpc/commit_customer_buyin_v2"
  $body = @{ p_buyin = $payload } | ConvertTo-Json -Depth 8

  $first = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' -Body $body
  $second = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' -Body $body

  if ($first.purchase_id -ne $requestId -or $first.duplicate -ne $false) {
    throw 'First RPC response did not report the expected new buy-in.'
  }
  if ($second.purchase_id -ne $requestId -or $second.duplicate -ne $true) {
    throw 'Exact retry was not reported as an idempotent duplicate.'
  }

  [pscustomobject]@{
    result = 'PASS'
    purchase_id = $requestId
    product_id = $productId
    inventory_unit_id = $unitId
    imei = $imei
    first_duplicate = $first.duplicate
    retry_duplicate = $second.duplicate
  } | ConvertTo-Json
}
finally {
  $plainPassword = $null
}
