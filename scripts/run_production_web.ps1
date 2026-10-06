<#
Run the Flutter web app locally against the main production Supabase project.
This uses the public publishable key; never put a service-role/secret key here.
Type PRODUCTION explicitly before launching to reduce accidental prod writes.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$productionUrl = 'https://kwxqukkdrpiyjnxxccil.supabase.co'
$productionPublishableKey = 'sb_publishable_-C9FG1q6o3vQZOC5hkHN1A_2BJ6e9sB'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Warning 'This launches the app against the MAIN production database. App actions may change real data.'
$confirmation = Read-Host 'Type PRODUCTION to continue'
if ($confirmation -cne 'PRODUCTION') {
  throw 'Cancelled. Production app was not started.'
}

Push-Location $repoRoot
try {
  flutter run -d chrome `
    "--dart-define=SUPABASE_URL=$productionUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$productionPublishableKey"

  if ($LASTEXITCODE -ne 0) {
    throw "Flutter production web run failed with exit code $LASTEXITCODE."
  }
}
finally {
  Pop-Location
}
