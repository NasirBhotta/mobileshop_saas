<#
Builds the optimized Flutter web app against the SEC-17 staging Supabase project.
Output is written to build/web for a Vercel Preview deployment.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stagingUrl = 'https://diqwalqgfkusqefomtdl.supabase.co'
$stagingPublishableKey = 'sb_publishable_emcHfOzD9niE_vCyNPmNuw_rAMbJGQI'
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
  flutter build web --release `
    "--dart-define=SUPABASE_URL=$stagingUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$stagingPublishableKey"

  if ($LASTEXITCODE -ne 0) {
    throw "Staging web release build failed with exit code $LASTEXITCODE."
  }

  if (-not (Test-Path (Join-Path $repoRoot 'build\web\index.html'))) {
    throw 'Flutter reported success but build/web/index.html was not created.'
  }

  Write-Host 'Staging release is ready in build/web. Deploy it as a Vercel Preview, not Production.'
}
finally {
  Pop-Location
}
