# dba-scripts repo structure

This document describes the current folder layout and the purpose of each area.

---

## Top-level layout

```text
sql/             Raw SQL scripts — SSMS-ready, paste-and-run
powershell/      Unique PowerShell scripts: orchestration, automation, DDL generators, OS tools
wrappers/        Thin PS wrappers — one per SQL script, mirrors sql/ categories
collectors/      Scheduled data collectors for trend analysis
helpers/         Repo utilities: SQL runner, triage, scaffolding, maintenance
tools/           Optional tooling: web UI, multi-server scripts
sql-operations/  Operational runbooks: change orders, checklists, installation, patching
docs/            Documentation: structure, roadmap, runbooks, quick-start
blog/            Draft blog posts for sqldba.blog (one post per script or workflow)
tests/           Pester test suite
output-files/    Generated output (gitignored — CSVs, healthcheck folders, reports)
```

---

## `sql/` — SQL scripts

All SQL scripts are single-result-set, read-only, and SSMS paste-and-run compatible. Every script has a standard header with `Script Name`, `Purpose`, `Author`, `Safe`, `Impact`, and `Requires`.

| Category | Contents |
|----------|----------|
| `sql/monitoring/` | Instance health, memory, MAXDOP, jobs, TempDB, DBCC, suspect pages, disk, config |
| `sql/performance/` | Waits, blocking, long queries, missing indexes, I/O, plan cache, active requests |
| `sql/backups/` | Coverage, history, DR estimates, restore generation, encryption status |
| `sql/security/` | Roles, permissions, orphans, weak logins, surface area, linked server security |
| `sql/migration/` | Risk assessment, compat audit, login audit, deprecated features, DDL generators |
| `sql/high-availability/` | AG replica state, AG latency, readable secondary usage |
| `sql/maintenance/` | Index maintenance jobs, backup jobs, housekeeping jobs, job status |
| `sql/lab/` | Dev/test-only scripts — blocking scenarios, test database creation |

See [script-catalog.md](script-catalog.md) for the full per-script list with descriptions.

---

## `powershell/` — Unique PowerShell scripts

These are scripts with genuine logic beyond "run the matching SQL file." DDL generators, orchestrators, automation, and OS-level tools. Not thin wrappers.

| Folder | Contents |
|--------|----------|
| `powershell/reporting/` | Invoke-HealthCheckCollection, Review-HealthCheckOutput, Invoke-AssessmentReport, Invoke-MultiServerHealthCheck, Get-ActiveRequests (with -IncludePlan), Get-BlockingChains (with -IncludePlan) |
| `powershell/migration/` | Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript, Generate-LinkedServerScript, Generate-RestoreWithMoveScript, Invoke-MigrationExport, Invoke-MigrationPreFlightCheck, Invoke-PreMigrationAssessment, Export-MigrationBaseline |
| `powershell/maintenance/` | Generate-BackupJobs, Generate-IndexMaintenanceJobs, Generate-MaintenanceJobs, Invoke-MaintenanceDeployment |
| `powershell/backup-automation/` | Backup-AllDatabases, Backup-SqlDatabases, Restore-AllDatabases, Generate-FullBackupScript, Generate-DiffBackupScript, Generate-TLogBackupScript, Generate-RestoreScript, Get-BackupAge |
| `powershell/inventory/` | Get-LargestFolders, Get-DiskSpaceSummary, Get-OldestBackupFolderFiles, Get-InstanceSnapshot, Get-InstanceHealthSummary |
| `powershell/lab/` | New-MultipleDatabases, Remove-DatabasesByPrefix, Run-CreateTestDatabases |

---

## `wrappers/` — Thin PS wrappers

One wrapper per SQL script. Each wrapper resolves the repo root, locates its matching `.sql` file, and delegates to `helpers/local-sql/Invoke-RepoSql.ps1`. Categories mirror `sql/` exactly so it is easy to find the wrapper for any SQL script.

| Folder | Wraps |
|--------|-------|
| `wrappers/monitoring/` | All `sql/monitoring/` scripts |
| `wrappers/performance/` | All `sql/performance/` scripts (except those handled via -IncludePlan) |
| `wrappers/backups/` | All `sql/backups/` scripts |
| `wrappers/security/` | All `sql/security/` scripts |
| `wrappers/migration/` | All `sql/migration/` Get-* scripts |
| `wrappers/high-availability/` | All `sql/high-availability/` scripts |
| `wrappers/maintenance/` | `sql/maintenance/` Get-* scripts |

---

## `collectors/` — Scheduled monitoring

Each collector pairs a `.sql` query with a PowerShell orchestrator (`Collect-*.ps1`) for scheduled historical data collection. They append timestamped rows to daily CSV files in `output-files/collectors/`.

| Collector | Data captured |
|-----------|---------------|
| `wait-stats` | Top wait types snapshot |
| `blocking` | Active blocking chains |
| `deadlocks` | Deadlock events from XEvent ring buffer |
| `tempdb` | TempDB file usage per session |
| `perfmon` | OS and SQL performance counters |
| `ag-health` | AG replica sync state and latency |
| `storage-io` | Database file I/O per volume |
| `database-growth` | Database size snapshots for growth trending |
| `vlf-count` | VLF count per database |
| `errorlog` | Error log entries by severity |
| `query-store` | Top queries from Query Store |
| `index-fragmentation` | Index fragmentation weekly snapshots |

---

## `helpers/` — Repo utilities

| Folder | Contents |
|--------|----------|
| `helpers/local-sql/` | `Invoke-RepoSql.ps1` (core runner), `Test-SqlConnectivity.ps1`, `Set-SqlConnection.ps1`, `Install-Prerequisites.ps1` |
| `helpers/triage/` | `Show-RepoOverview.ps1`, `Find-UsefulScript.ps1`, `Quick-TaskRouter.ps1` |
| `helpers/scaffolding/` | `Generate-NextPowerShell.ps1` (stub new wrappers quickly) |
| `helpers/maintenance/` | `Clear-OutputFiles.ps1`, `update-powershell.ps1` |
| `helpers/multi-server-query/` | `New-MultiServerScript.ps1` — wraps any SQL or PS in a multi-server foreach loop |

---

## `tools/` — Optional tooling

| Item | Purpose |
|------|---------|
| `tools/web-ui/Start-WebUi.ps1` | Local web interface for browsing scripts and visualising CSV output. Optional — not required for any core workflow. |
| `sql-operations/multi-server-scripts/` | Self-contained scripts for running operations across multiple servers simultaneously |

---

## `sql-operations/` — Operational runbooks

Runbook-style content for planned DBA work: change orders, checklists, SQL templates, and installation scripts. Not diagnostic scripts — these are for executing changes safely.

| Subfolder | Contents |
|-----------|----------|
| `change-orders/` | Change order documents for AlwaysOn failover, server migration, SQL upgrade |
| `change-templates/` | SQL templates for CDC, TDE, mirroring, AG, statistics, DBCC, patching, installation |
| `checklists/` | Step-by-step checklists for AG migration, DR failover, server replacement, version upgrade |
| `runbooks/` | Full runbooks for standalone migration, AG cluster migration, OS upgrade, edition change, version upgrade |
| `installation/` | SQL Server install, configure, validate, and uninstall scripts |
| `patches/` | CU and SSMS patch installation scripts |
| `rollback/` | Migration rollback playbook |

---

## Adding new content

**New SQL script:** `sql/<category>/Get-Something.sql` — use the standard header from `CLAUDE.md`.

**New PS wrapper:** Copy any existing wrapper from `wrappers/<category>/`, update the SQL path and description. The `$PSScriptRoot '..\..'` path resolves correctly at this depth.

**New unique PS script:** Add to the appropriate `powershell/<subfolder>/`. If no matching subfolder exists, use `powershell/reporting/` for query/reporting scripts or `powershell/inventory/` for environment/config scripts.

**New collector:** Follow the pattern in any existing `collectors/<name>/` — one `.sql`, one `Collect-*.ps1`, one `README.md` with SQL Agent T-SQL.
