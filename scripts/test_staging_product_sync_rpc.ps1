<#
Staging-only positive test for upsert_inventory_product_v2.
Verifies initial stock is set once and a later cached stock snapshot cannot
overwrite it during a product edit.
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
$publishableKey = Read-Required 'Staging publishable key'
$email = Read-Required 'Authorized test-user email'
$password = Read-Host 'Authorized test-user password' -AsSecureString
$plainPassword = $null

try {
  $plainPassword = Convert-SecureString $password
  $auth = Invoke-RestMethod -Method Post `
    -Uri "$stagingUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $publishableKey } -ContentType 'application/json' `
    -Body (@{ email = $email; password = $plainPassword } | ConvertTo-Json)
  if ([string]::IsNullOrWhiteSpace($auth.access_token)) { throw 'Authentication returned no access token.' }

  $headers = @{ apikey = $publishableKey; Authorization = "Bearer $($auth.access_token)" }
  $productId = [guid]::NewGuid().ToString()
  $firstPayload = @{
    id = $productId
    branch_id = '22222222-2222-4222-8222-222222222222'
    name = "SEC-17 Product $productId"
    sku = "SEC17-$($productId.Substring(0, 8))"
    sale_price = 25000
    cost_price = 20000
    imei_tracked = $false
    is_active = $true
    reorder_threshold = 3
    stock = 4
  }
  $rpcUri = "$stagingUrl/rest/v1/rpc/upsert_inventory_product_v2"
  $first = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' `
    -Body (@{ p_product = $firstPayload } | ConvertTo-Json -Depth 8)

  $retryPayload = $firstPayload.Clone()
  $retryPayload.sale_price = 26000
  $retryPayload.reorder_threshold = 6
  $retryPayload.stock = 999
  $second = Invoke-RestMethod -Method Post -Uri $rpcUri -Headers $headers -ContentType 'application/json' `
    -Body (@{ p_product = $retryPayload } | ConvertTo-Json -Depth 8)

  $product = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/products?id=eq.$productId&select=id,sale_price,reorder_threshold" `
    -Headers $headers
  $inventory = Invoke-RestMethod -Method Get `
    -Uri "$stagingUrl/rest/v1/inventory?product_id=eq.$productId&branch_id=eq.22222222-2222-4222-8222-222222222222&select=quantity,reorder_threshold" `
    -Headers $headers

  if ($first.created -ne $true -or $second.created -ne $false) { throw 'Unexpected create/retry response.' }
  if (@($product).Count -ne 1 -or @($inventory).Count -ne 1) { throw 'Expected one product and one inventory row.' }
  if ($product[0].sale_price -ne 26000 -or $inventory[0].quantity -ne 4 -or $inventory[0].reorder_threshold -ne 6) {
    throw "Product/inventory invariant failed: sale_price=$($product[0].sale_price), quantity=$($inventory[0].quantity), reorder_threshold=$($inventory[0].reorder_threshold)"
  }

  [pscustomobject]@{
    result = 'PASS'
    product_id = $productId
    first_created = $first.created
    retry_created = $second.created
    sale_price_after_edit = $product[0].sale_price
    quantity_after_cached_stock_retry = $inventory[0].quantity
    reorder_threshold_after_edit = $inventory[0].reorder_threshold
  } | ConvertTo-Json
}
finally {
  $plainPassword = $null
}
