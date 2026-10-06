# Free-plan staging schema copy

Use this only after confirming the staging Supabase project is empty. It copies the **public schema only** from production: tables, indexes, constraints, functions and RLS policies. It does not copy table rows, Auth users, Storage objects or files.

## Before you begin

1. Install the free PostgreSQL command-line tools so `pg_dump` and `psql` are available in PowerShell.
2. In each Supabase project, open **Connect**, choose **Session pooler**, then use **View parameters**. Copy its host and user; keep the default port `5432` and database name `postgres`. Use production as the source and the `diq...` project as staging. Do not construct a `db.<project-ref>` host manually: that direct connection can require IPv6.
3. Get each project's database password from its own Database settings. Do not send either password here.

## Run

Open PowerShell in this repository and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\clone_public_schema_to_staging.ps1
```

The script hides password input, refuses an identical source/target database, checks that the dump has no data statements, asks you to type `STAGING`, and imports the schema inside one staging transaction.

## After success

Run `docs/security_sec17_staging_preflight.sql` in the **staging** SQL Editor. Do not run a SEC-17 migration until that query reports the required prerequisites.

## Limits

Supabase project configuration, Storage buckets/files, Edge Functions and Auth settings are outside `public` and are not copied. The staging tests use synthetic users and data, so those elements can be configured separately if a test needs them.
