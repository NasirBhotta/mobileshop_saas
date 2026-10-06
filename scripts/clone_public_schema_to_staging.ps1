# Copies only the public schema from production to an EMPTY staging database.
# Production is read-only; staging is the only import target.
# Schema-only export excludes table rows, Auth users, Storage objects and files.
# Source and target host must differ; the script rejects top-level COPY/INSERT data.
# PostgreSQL command-line tools (pg_dump and psql) must be on PATH.
# Never paste database passwords into chat; the prompts do not echo them.

  [CmdletBinding()]
  param()

  $ErrorActionPreference = 'Stop'

  function Read-Required([string] $prompt, [string] $defaultValue = '') {
    $value = Read-Host "$prompt$(if ($defaultValue) { " [$defaultValue]" })"
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $defaultValue }
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$prompt is required." }
    return $value.Trim()
  }

  function Convert-SecureString([securestring] $value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
    try {
      return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
  }

  foreach ($command in 'pg_dump', 'psql') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
      throw "'$command' was not found on PATH. Install PostgreSQL command-line tools, then run this script again."
    }
  }

  Write-Host 'Production connection (read-only export):' -ForegroundColor Cyan
  $productionHost = Read-Required 'Production database host'
  $productionPort = Read-Required 'Production database port' '5432'
  $productionDatabase = Read-Required 'Production database name' 'postgres'
  $productionUser = Read-Required 'Production database user' 'postgres'
  $productionPassword = Read-Host 'Production database password' -AsSecureString

  Write-Host 'Staging connection (empty target only):' -ForegroundColor Cyan
  $stagingHost = Read-Required 'Staging database host'
  $stagingPort = Read-Required 'Staging database port' '5432'
  $stagingDatabase = Read-Required 'Staging database name' 'postgres'
  $stagingUser = Read-Required 'Staging database user' 'postgres'
  $stagingPassword = Read-Host 'Staging database password' -AsSecureString

  if ($productionHost.Trim().ToLowerInvariant() -eq $stagingHost.Trim().ToLowerInvariant() -and
    $productionPort -eq $stagingPort -and
    $productionDatabase -eq $stagingDatabase) {
    throw 'Production and staging point to the same database. Import refused.'
  }

  $confirmation = Read-Host "Type STAGING to replace the public schema on $stagingHost"
  if ($confirmation -cne 'STAGING') {
    throw 'Confirmation did not match. Nothing was changed.'
  }

  $dumpPath = Join-Path $env:TEMP ("mobileshop-public-schema-{0}.sql" -f [guid]::NewGuid())
$extensionsPath = Join-Path $env:TEMP ("mobileshop-public-extensions-{0}.sql" -f [guid]::NewGuid())
  $productionPlaintext = $null
  $stagingPlaintext = $null

  try {
    $productionPlaintext = Convert-SecureString $productionPassword
    $env:PGPASSWORD = $productionPlaintext

  # The target is verified empty. --schema-only excludes rows; -n public
  # intentionally excludes auth/storage data. Do not use --clean here: its
  # ALTER TABLE ... DROP CONSTRAINT statements require source tables to exist.
    & pg_dump `
      --host $productionHost --port $productionPort --username $productionUser `
    --dbname $productionDatabase --schema public --schema-only `
      --no-owner --no-privileges --file $dumpPath
    if ($LASTEXITCODE -ne 0) { throw 'Production schema export failed.' }

  # A new Supabase project already has the public schema. Keep that schema so
  # extensions can be installed into it, then remove only pg_dump's duplicate
  # CREATE SCHEMA statement before the application DDL is imported.
  $normalizedDumpPath = "$dumpPath.normalized"
  Get-Content -LiteralPath $dumpPath |
    Where-Object { $_ -ne 'CREATE SCHEMA public;' } |
    Set-Content -LiteralPath $normalizedDumpPath -Encoding utf8
  Move-Item -LiteralPath $normalizedDumpPath -Destination $dumpPath -Force

  # pg_dump does not emit CREATE EXTENSION. Recreate extensions installed in
  # production's public schema before importing indexes/functions that use them
  # (for example, pg_trgm's gin_trgm_ops).
  $extensionSql = & psql `
    --host $productionHost --port $productionPort --username $productionUser `
    --dbname $productionDatabase --tuples-only --no-align --quiet `
    --command "select format('CREATE EXTENSION IF NOT EXISTS %I WITH SCHEMA public;', extname) from pg_extension extension join pg_namespace namespace on namespace.oid = extension.extnamespace where namespace.nspname = 'public' and extname <> 'plpgsql' order by extname"
  if ($LASTEXITCODE -ne 0) { throw 'Production extension inventory failed.' }
  Set-Content -LiteralPath $extensionsPath -Value $extensionSql -Encoding utf8

  # A schema can legitimately contain INSERT text inside a PL/pgSQL function.
  # pg_dump data sections use unindented, uppercase COPY/INSERT commands.
  $dataStatements = Select-String -LiteralPath $dumpPath -CaseSensitive -Pattern '^(COPY|INSERT INTO) public\.'
    if ($dataStatements) {
      throw 'Export unexpectedly contains data statements. Staging import refused.'
    }

    $stagingPlaintext = Convert-SecureString $stagingPassword
    $env:PGPASSWORD = $stagingPlaintext
    & psql `
      --host $stagingHost --port $stagingPort --username $stagingUser `
      --dbname $stagingDatabase --set ON_ERROR_STOP=1 --single-transaction `
    --file $extensionsPath `
      --file $dumpPath
    if ($LASTEXITCODE -ne 0) { throw 'Staging import failed and was rolled back.' }

    Write-Host 'Schema-only staging import completed. Run docs/security_sec17_staging_preflight.sql next.' -ForegroundColor Green
  }
  finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    $productionPlaintext = $null
    $stagingPlaintext = $null
    if (Test-Path -LiteralPath $dumpPath) {
      Remove-Item -LiteralPath $dumpPath -Force
    }
  if (Test-Path -LiteralPath "$dumpPath.normalized") {
    Remove-Item -LiteralPath "$dumpPath.normalized" -Force
  }
  if (Test-Path -LiteralPath $extensionsPath) {
    Remove-Item -LiteralPath $extensionsPath -Force
  }
  }
