<#
Read/write authorization probe for the synthetic SEC-17 staging customers.
Uses the Tenant A owner session and verifies Tenant A data is visible while
Tenant B's known fixture row cannot be selected or changed.
Password is prompted securely and is never written to disk or printed.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stagingUrl = 'https://diqwalqgfkusqefomtdl.supabase.co'
$publishableKey = 'sb_publishable_emcHfOzD9niE_vCyNPmNuw_rAMbJGQI'
$email = 'sec17.staging.owner@gmail.com'
$tenantAControlId = '77777777-7777-4777-8777-777777777777'
$tenantBTargetId = '66666666-6666-4666-8666-666666666666'
$tenantAProductControlId = '88888888-8888-4888-8888-888888888888'
$tenantBProductTargetId = '99999999-9999-4999-8999-999999999999'

$password = Read-Host 'Staging Tenant A owner password' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
try { $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }

try {
  $auth = Invoke-RestMethod -Method Post `
    -Uri "$stagingUrl/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $publishableKey } `
    -ContentType 'application/json' `
    -Body (@{ email = $email; password = $plainPassword } | ConvertTo-Json)
  if ([string]::IsNullOrWhiteSpace($auth.access_token)) {
    throw 'Staging login returned no access token.'
  }

  $headers = @{
    apikey = $publishableKey
    Authorization = "Bearer $($auth.access_token)"
    Prefer = 'return=representation'
  }
  $ownUri = "$stagingUrl/rest/v1/customers?id=eq.$tenantAControlId&select=id,tenant_id,full_name"
  $foreignUri = "$stagingUrl/rest/v1/customers?id=eq.$tenantBTargetId&select=id,tenant_id,full_name"
  $ownProductUri = "$stagingUrl/rest/v1/products?id=eq.$tenantAProductControlId&select=id,tenant_id,name"
  $foreignProductUri = "$stagingUrl/rest/v1/products?id=eq.$tenantBProductTargetId&select=id,tenant_id,name"
  # Invoke-RestMethod may return $null for a JSON [] response. Do not wrap
  # that null directly in @(...), because PowerShell counts it as one row.
  $ownResult = Invoke-RestMethod -Method Get -Uri $ownUri -Headers $headers
  $foreignResult = Invoke-RestMethod -Method Get -Uri $foreignUri -Headers $headers
  $ownProductResult = Invoke-RestMethod -Method Get -Uri $ownProductUri -Headers $headers
  $foreignProductResult = Invoke-RestMethod -Method Get -Uri $foreignProductUri -Headers $headers
  $ownRows = @()
  $foreignRows = @()
  $ownProductRows = @()
  $foreignProductRows = @()
  if ($null -ne $ownResult) { $ownRows = @($ownResult) }
  if ($null -ne $foreignResult) { $foreignRows = @($foreignResult) }
  if ($null -ne $ownProductResult) { $ownProductRows = @($ownProductResult) }
  if ($null -ne $foreignProductResult) { $foreignProductRows = @($foreignProductResult) }

  if ($ownRows.Count -ne 1 -or $ownRows[0].tenant_id -ne '11111111-1111-4111-8111-111111111111') {
    throw 'Positive control failed: Tenant A owner could not read the Tenant A fixture row.'
  }
  if ($foreignRows.Count -ne 0) {
    $visible = $foreignRows |
      Select-Object id, tenant_id, full_name |
      ConvertTo-Json -Compress
    throw "FAIL: Tenant A owner read a customer row belonging to Tenant B: $visible"
  }
  if ($ownProductRows.Count -ne 1 -or $ownProductRows[0].tenant_id -ne '11111111-1111-4111-8111-111111111111') {
    throw 'Positive control failed: Tenant A owner could not read the Tenant A product fixture row.'
  }
  if ($foreignProductRows.Count -ne 0) {
    $visible = $foreignProductRows |
      Select-Object id, tenant_id, name |
      ConvertTo-Json -Compress
    throw "FAIL: Tenant A owner read a product row belonging to Tenant B: $visible"
  }

  $patchRows = @()
  try {
    $patchResult = Invoke-RestMethod -Method Patch -Uri $foreignUri -Headers $headers `
      -ContentType 'application/json' `
      -Body (@{ full_name = 'SEC-17 UNAUTHORIZED CHANGE' } | ConvertTo-Json)
    if ($null -ne $patchResult) { $patchRows = @($patchResult) }
  }
  catch {
    $statusCode = [int]$_.Exception.Response.StatusCode
    if ($statusCode -notin @(401, 403)) { throw }
  }
  if ($patchRows.Count -ne 0) {
    throw 'FAIL: Tenant A owner updated a customer row belonging to Tenant B.'
  }

  $productPatchRows = @()
  try {
    $productPatchResult = Invoke-RestMethod -Method Patch -Uri $foreignProductUri -Headers $headers `
      -ContentType 'application/json' `
      -Body (@{ name = 'SEC-17 UNAUTHORIZED PRODUCT CHANGE' } | ConvertTo-Json)
    if ($null -ne $productPatchResult) { $productPatchRows = @($productPatchResult) }
  }
  catch {
    $statusCode = [int]$_.Exception.Response.StatusCode
    if ($statusCode -notin @(401, 403)) { throw }
  }
  if ($productPatchRows.Count -ne 0) {
    throw 'FAIL: Tenant A owner updated a product row belonging to Tenant B.'
  }

  [pscustomobject]@{
    result = 'PASS'
    tenant_a_control_visible = $true
    tenant_b_target_rows_visible = $foreignRows.Count
    tenant_b_target_update_rows = $patchRows.Count
    tenant_a_product_control_visible = $true
    tenant_b_product_rows_visible = $foreignProductRows.Count
    tenant_b_product_update_rows = $productPatchRows.Count
  } | ConvertTo-Json
}
finally {
  $plainPassword = $null
  $auth = $null
}
