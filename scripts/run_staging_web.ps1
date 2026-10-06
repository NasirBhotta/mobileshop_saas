<#
Run the Flutter web app locally against the SEC-17 staging Supabase project.
This is a public publishable client key, not a service-role/secret key.
#>

$ErrorActionPreference = 'Stop'

$stagingUrl = 'https://diqwalqgfkusqefomtdl.supabase.co'
$stagingPublishableKey = 'sb_publishable_emcHfOzD9niE_vCyNPmNuw_rAMbJGQI'

flutter run -d chrome `
  "--dart-define=SUPABASE_URL=$stagingUrl" `
  "--dart-define=SUPABASE_ANON_KEY=$stagingPublishableKey"

if ($LASTEXITCODE -ne 0) {
  throw "Flutter web run failed with exit code $LASTEXITCODE."
}
