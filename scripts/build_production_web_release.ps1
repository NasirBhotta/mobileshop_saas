<#
Builds the optimized Flutter web app against the MAIN production Supabase project.
The result is written to build/web. Database-changing actions use real data.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$productionUrl = 'https://kwxqukkdrpiyjnxxccil.supabase.co'
$productionPublishableKey = 'sb_publishable_-C9FG1q6o3vQZOC5hkHN1A_2BJ6e9sB'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Warning 'This builds the web app against MAIN production. Tests and app actions can read or change live data.'
$confirmation = Read-Host 'Type PRODUCTION to build the production-connected app'
if ($confirmation -cne 'PRODUCTION') {
  throw 'Cancelled. Production build was not created.'
}

Push-Location $repoRoot
try {
  flutter build web --release `
    "--dart-define=SUPABASE_URL=$productionUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$productionPublishableKey"

  if ($LASTEXITCODE -ne 0) {
    throw "Production web release build failed with exit code $LASTEXITCODE."
  }

  if (-not (Test-Path (Join-Path $repoRoot 'build\web\index.html'))) {
    throw 'Flutter reported success but build/web/index.html was not created.'
  }

  Write-Host 'Production release is ready in build/web. Deploy only when you intend to expose the live app.'
}
finally {
  Pop-Location
}
