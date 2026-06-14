# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A production SQL Server DBA toolkit for Peter Whyte (sqldba.blog). It contains read-only diagnostic SQL scripts, PowerShell orchestration wrappers, a healthcheck collection and review workflow, security audit scripts, and migration inventory helpers. All scripts target SQL Server 2012+. Output goes to `output-files/`.

This repository is **not** a collection of scripts — it is an operational toolkit for managing SQL Server estates. Everything fits into one of three layers:

1. **SQL layer** — DMV queries, performance analysis, configuration inspection, backup validation, blocking/locking analysis
2. **PowerShell layer** — automation across servers, execution of SQL at scale, scheduling, orchestration, reporting, environment-level operations
3. **Hybrid layer** — PowerShell executes SQL scripts, results collected, transformed, and reported; operational workflows (backup checks, inventory, monitoring)

## Core principles

- Do **not** change business logic unless required for correctness or safety
- Preserve intent of all scripts
- Prioritise production safety over clever optimisation
- Avoid overengineering

## How to run scripts

The three entry points, in order of preference:

```powershell
# 1. Root launcher — fuzzy name match, searches all powershell/ subfolders
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-WaitStatistics -ServerInstance MYSERVER\INST01 -OutputFormat Csv

# 2. Direct wrapper — explicit path, passes all params through
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Get-WaitStatistics.ps1 -ServerInstance . -OutputFormat Csv

# 3. SQL directly via the repo runner (for SSMS-style results in terminal)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\local-sql\Invoke-RepoSql.ps1 -ScriptPath .\sql\performance\Get-WaitStatistics.sql -ServerInstance .
```

Full healthcheck workflow:
```powershell
# Collect 27 scripts, save CSVs to output-files\healthcheck\<server>-<timestamp>\
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance .

# Review the latest collection folder and surface CRITICAL / WARNING / INFO findings
.\powershell\reporting\Review-HealthCheckOutput.ps1

# Or target a specific folder
.\powershell\reporting\Review-HealthCheckOutput.ps1 -FolderPath ".\output-files\healthcheck\.-20260529-185000" -OutputFormat Csv
```

Preflight and discovery:
```powershell
.\tools\triage\Show-RepoOverview.ps1                          # inventory: script counts by category
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking        # find scripts by keyword
.\tools\local-sql\Test-SqlConnectivity.ps1 -ServerInstance .  # verify SQL connectivity
.\tools\maintenance\Clear-OutputFiles.ps1                     # wipe output-files\ before a fresh run
```

## Layout

**Use `sql/`, `powershell/`, or `wrappers/` for all new work.**

```text
sql/
  monitoring/         — health, memory, MAXDOP, jobs, TempDB, DBCC, suspect pages, instance config
  performance/        — waits, blocking, long queries, missing indexes, I/O, plan cache, active requests
  high-availability/  — AG replica state, AG latency (guards against non-AG instances)
  backups/            — coverage, history, DR estimates, restore generation
  security/           — roles, permissions, orphans, weak logins, surface area
  migration/          — risk assessment, compat audit, login audit, deprecated features, DDL generators

powershell/
  reporting/          — Invoke-HealthCheckCollection, Review-HealthCheckOutput, Invoke-AssessmentReport,
                        Invoke-MultiServerHealthCheck, Get-ActiveRequests, Get-BlockingChains (with -IncludePlan)
  migration/          — Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript,
                        Generate-LinkedServerScript, Generate-RestoreWithMoveScript,
                        Invoke-MigrationExport, Invoke-MigrationPreFlightCheck, Invoke-PreMigrationAssessment,
                        Export-MigrationBaseline
  maintenance/        — Generate-BackupJobs, Generate-IndexMaintenanceJobs, Generate-MaintenanceJobs,
                        Invoke-MaintenanceDeployment
  backup-automation/  — Backup-AllDatabases, Backup-SqlDatabases, Restore-AllDatabases,
                        Generate-FullBackupScript, Generate-DiffBackupScript, Generate-TLogBackupScript,
                        Generate-RestoreScript, Get-BackupAge
  inventory/          — Get-LargestFolders, Get-DiskSpaceSummary, Get-OldestBackupFolderFiles,
                        Get-InstanceSnapshot, Get-InstanceHealthSummary
  multi-server/       — MultiServer-Get*.ps1 scripts (disk, wait stats, patch level, blocking, etc.)
  lab/                — lab and test database scripts (dev/test only)

wrappers/             — thin PS wrappers: one per SQL script, mirrors sql/ category structure.
  monitoring/         — wrappers for all sql/monitoring/ scripts
  performance/        — wrappers for all sql/performance/ scripts
  backups/            — wrappers for all sql/backups/ scripts
  security/           — wrappers for all sql/security/ scripts
  migration/          — wrappers for all sql/migration/ Get-* scripts
  high-availability/  — wrappers for all sql/high-availability/ scripts
  maintenance/        — wrappers for sql/maintenance/ Get-* scripts

collectors/
  Each collector pairs a SQL file with a PS orchestrator for scheduled historical data collection.
  Naming: lowercase-hyphenated (blocking.sql, wait-stats.sql) — these are recorders, not getters.
  Output: appends timestamped rows to daily CSV files for trend analysis and post-incident review.
  Collectors: ag-health, blocking, database-growth, deadlocks, perfmon, storage-io, tempdb, wait-stats

web-ui/               — browser UI: Start-WebUi.ps1, Restart-WebUi.ps1, Generate-ScriptIndex.ps1

tools/
  local-sql/    — Invoke-RepoSql.ps1 (the core runner), Set-SqlConnection.ps1, Test-SqlConnectivity.ps1
  triage/       — Show-RepoOverview.ps1, Find-UsefulScript.ps1, Quick-TaskRouter.ps1
  scaffolding/  — Generate-NextPowerShell.ps1, New-MultiServerScript.ps1
  maintenance/  — Clear-OutputFiles.ps1, update-powershell.ps1

admin/
  installation/ — SQL Server install, configure, validate, uninstall
  patching/     — CU updates (install-cu.ps1), SSMS updates, patch summary

docs/
  quick-start.md, roadmap.md, runbook.md
  ops/          — change orders, checklists, runbooks, rollback playbooks, change-templates

output-files/         — generated CSVs, healthcheck folders, reviews
```

## Running against a remote server

All scripts that call `Invoke-RepoSql.ps1` honour three session-level environment variables. Set them once with `Set-SqlConnection.ps1` and every script picks them up automatically for the rest of the session — no need to repeat `-ServerInstance` on every call.

```powershell
# Set remote server for this session (Windows auth)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# SQL auth (prompts for password)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa

# Named instance with non-default port
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance "PROD01\INST01,14330"

# See what is currently active
.\tools\local-sql\Set-SqlConnection.ps1 -Show

# Reset to local (.) Windows auth
.\tools\local-sql\Set-SqlConnection.ps1 -Clear
```

Or pass `-ServerInstance` directly on any individual call:

```powershell
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019
.\powershell\reporting\Get-WaitStatistics.ps1 -ServerInstance PROD01\SQL2019 -OutputFormat Csv
```

Env vars used internally: `$env:DBASCRIPTS_SERVER`, `$env:DBASCRIPTS_USER`, `$env:DBASCRIPTS_PASS`. Explicit params always win over env vars.

### DDL generator scripts

`powershell/migration/Generate-*.ps1` scripts work differently from normal wrappers — they do **not** go through the CSV pipeline. They call `Invoke-Sqlcmd` with `MaxCharLength 2000000` (or `sqlcmd.exe -y 0`) to capture the full `NVARCHAR(MAX)` DDL string and write it to a `.sql` file in `output-files\migration\`. Never call these through `Invoke-RepoSql.ps1`.

```powershell
# Migration: generate all three scripts from source server
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-LoginScript.ps1
.\powershell\migration\Generate-AgentJobScript.ps1
.\powershell\migration\Generate-UserMappingScript.ps1
# Output: output-files\migration\*.sql  — review, edit owners, run on target
```

## How PowerShell wrappers work

Every script in `powershell/**/*.ps1` (except utility scripts and orchestrators) is a thin wrapper:

1. Resolves `$repoRoot` as two levels up from `$PSScriptRoot`
2. Builds `$sqlScript = Join-Path $repoRoot 'sql\<category>\<Name>.sql'`
3. Delegates to `tools\local-sql\Invoke-RepoSql.ps1` with `-ScriptPath`, `-ServerInstance`, `-Database`, `-OutputFormat`, `-OutputPath`

`Invoke-RepoSql.ps1` tries `Invoke-Sqlcmd` first (SqlServer module), falls back to `sqlcmd.exe`. Always writes a CSV to `output-files\reviews\<category>\<scriptname>-<timestamp>.csv` and prints a table preview. If neither tool is available it throws.

`run.ps1` resolves script by name fuzzy match → `& $target @Arguments`. It searches `powershell/`, `wrappers/`, `tools/`, `sql/` recursively. Throws if more than one match — callers must be specific.

**PowerShell script rules:**
- Classify script type in `.NOTES`: `runner` / `automation` / `hybrid`
- State target scope: `single server` or `multi-server`
- Classify risk in `.NOTES`: `RiskLevel : SAFE` / `MEDIUM` / `HIGH IMPACT`
- Separate SQL logic from orchestration — SQL lives in external `.sql` files
- Add error handling; ensure idempotent behaviour where possible

## SQL script standards

Every SQL script must have this header block then the two safety annotations:

```sql
/*
Script Name : Get-ExampleScript
Category    : performance-troubleshooting
Purpose     : One-line description of what this returns.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
```

`Safe` values: `Read-only` / `Writes data` / `Creates objects`  
`Impact` values: `Low` / `Medium` / `High`

**SQL script rules:**
- Remove or flag unsafe patterns: `WITH (NOLOCK)` (explain risk if present), deprecated catalog views (`sys.sysprocesses`, `sys.sysobjects` etc.)
- Prefer modern DMVs — `sys.objects` not `sys.sysobjects`, `sys.server_principals` not `sys.syslogins`
- No `USE database; GO` — `Invoke-Sqlcmd` does not support `GO` batch separators; pass `-Database` at execution time
- `OUTER APPLY` not `CROSS APPLY` when the applied function may return no rows
- No trailing blank lines; 0–1 blank lines at end of file
- Keep output readable and deterministic

**`docs/standards.md` is outdated** — it shows an older header format. The format above is what the scripts actually use.

## Adding new scripts

New SQL script: `sql/<category>/Get-Something.sql` using the header above.

New PS wrapper: copy any existing wrapper in `wrappers/<category>/` (matching the sql/ category), update the three variables (`syn`, `$sqlScript` path, `Write-Host` message). The `$PSScriptRoot '..\..'` path is correct — `wrappers/<category>/` is the same depth as `sql/<category>/`.

If there is no matching subcategory, add to `powershell/reporting/` for read/query scripts or `powershell/inventory/` for environment/config scripts.

**When refactoring an existing script, summarise:** improved script, risk classification (`SAFE` / `MEDIUM` / `HIGH IMPACT`), key changes (bullets), suggested folder placement.

**For each major script, document:** purpose in operational terms, example output interpretation, when **not** to use it, required permissions.

## Healthcheck collection — what it covers

`Invoke-HealthCheckCollection.ps1` runs 27 scripts and saves named CSVs:

| CSV label | SQL script |
|-----------|-----------|
| server-info | Get-VersionAndEdition.sql |
| os-hardware | Get-OsAndHardwareInfo.sql |
| database-health | Get-DatabaseHealth.sql |
| database-sizes | Get-DatabaseSizesAndFreeSpace.sql |
| database-files | Get-DatabaseFilesDetail.sql |
| backup-times | Get-LastDatabaseBackupTimes.sql |
| backup-coverage | Get-BackupCoverage.sql |
| tlog-usage | Get-TransactionLogSizeAndUsage.sql |
| memory-config | Get-MemoryConfigurationAndUsage.sql |
| wait-stats | Get-WaitStatistics.sql |
| active-sessions | Get-ActiveSessions.sql |
| tempdb-usage | Get-TempdbUsage.sql |
| job-failures | Get-SqlAgentJobFailureSummary.sql |
| recent-errors | Get-RecentErrorLogEntries.sql |
| dbcc-checkdb | Get-LastDbccCheckdb.sql |
| suspect-pages | Get-SuspectPages.sql |
| io-usage | Get-DatabaseIoUsage.sql |
| disk-space | Get-DiskSpace.sql |
| growth-risk | Get-DatabaseGrowthRisk.sql |
| security-surface-area | Get-DatabaseMailAndXpCmdShell.sql |
| weak-logins | Get-WeakLoginSettings.sql |
| missing-indexes | Get-MissingIndexes.sql |
| tempdb-config | Get-TempDbConfiguration.sql |
| plan-cache | Get-PlanCacheHealth.sql |
| linked-server-security | Get-LinkedServerSecurity.sql |
| vlf-count | Get-VlfCount.sql |
| maintenance-jobs | Get-MaintenanceJobStatus.sql (msdb) |

`Review-HealthCheckOutput.ps1` reads those CSVs and fires on: databases not ONLINE, missing backups, stale full/log backups, tlog >80% used, auto-shrink, auto-close, percent-based autogrowth, DBCC CHECKDB not run in >7 days, any suspect pages (CRITICAL), SA enabled (CRITICAL), weak SQL login settings, I/O latency >50ms, specific wait type patterns (PAGEIOLATCH, WRITELOG, RESOURCE_SEMAPHORE, CXPACKET), max server memory unconfigured, data files <10% free, VLF count >200 (WARNING) or >1000 (CRITICAL), and DBA maintenance job missing/failed/disabled.

## Important caveats

- AG scripts (`sql/high-availability/Get-AvailabilityGroupReplicaState.sql`, `Get-AvailabilityGroupLatency.sql`) guard against non-AG instances and return a status row instead of throwing.
- Multi-result-set SQL scripts cannot be cleanly exported as a single CSV via `Invoke-RepoSql.ps1`. All canonical `sql/` scripts are single-result-set by design.
- `output-files/` has no `.gitignore` protection — CSV files accumulate there and should not be committed.
- `docs/catalog.md` is outdated and references old `categories/` paths. Ignore it; use the `sql/` folder tree directly.
