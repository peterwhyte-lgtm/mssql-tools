# mssql-tools repo structure

This document describes the current folder layout and the purpose of each area.

---

## Top-level layout

```text
database-admin/     All SQL scripts, PS orchestrators, migration tools, collectors, ops docs
web-ui/             Browser UI + thin PS wrappers (one per SQL script)
tools/              Repo utilities: SQL runner, triage, scaffolding, maintenance
docs/               Documentation: structure, roadmap, runbooks, quick-start
blog/               Draft blog posts for sqldba.blog
tests/              Pester test suite
output-files/       Generated output (gitignored — CSVs, healthcheck folders, reports)
```

---

## `database-admin/sql-scripts/` — SQL scripts

All SQL scripts are single-result-set, read-only, and SSMS paste-and-run compatible. Every script has a standard header with `Script Name`, `Purpose`, `Author`, `Safe`, `Impact`, and `Requires`.

| Category | Contents |
|----------|----------|
| `sql-scripts/monitoring/` | Instance health, memory, MAXDOP, jobs, TempDB, DBCC, suspect pages, disk, config |
| `sql-scripts/performance/` | Waits, blocking, long queries, missing indexes, I/O, plan cache, active requests |
| `sql-scripts/backups/` | Coverage, history, DR estimates, restore generation, encryption status |
| `sql-scripts/security/` | Roles, permissions, orphans, weak logins, surface area, linked server security |
| `sql-scripts/ha-dr/` | AG replica state, AG latency, readable secondary usage |
| `sql-scripts/maintenance/` | Index maintenance jobs, backup jobs, housekeeping jobs, job status |
| `sql-scripts/lab/` | Dev/test-only scripts — blocking scenarios, test database creation |

Migration SQL scripts live separately at `database-admin/migration/sql/`. See [script-catalog.md](script-catalog.md) for the full list.

---

## `database-admin/powershell-scripts/` — Unique PowerShell scripts

Scripts with genuine logic beyond "run the matching SQL file." Orchestrators, automation, and OS-level tools.

| Folder | Contents |
|--------|----------|
| `reporting/` | Invoke-HealthCheckCollection, Review-HealthCheckOutput, Invoke-AssessmentReport, Invoke-MultiServerHealthCheck, Get-ActiveRequests (with -IncludePlan), Get-BlockingChains (with -IncludePlan) |
| `maintenance/` | Generate-BackupJobs, Generate-IndexMaintenanceJobs, Generate-MaintenanceJobs, Invoke-MaintenanceDeployment |
| `backup-automation/` | Backup-AllDatabases, Backup-SqlDatabases, Restore-AllDatabases, Generate-FullBackupScript, Generate-DiffBackupScript, Generate-TLogBackupScript, Generate-RestoreScript, Get-BackupAge |
| `inventory/` | Get-LargestFolders, Get-DiskSpaceSummary, Get-OldestBackupFolderFiles, Get-InstanceSnapshot, Get-InstanceHealthSummary |
| `multi-server/` | MultiServer-Get*.ps1 and MultiServer-*.ps1 scripts for fleet-wide operations |
| `lab/` | New-MultipleDatabases, Remove-DatabasesByPrefix, Run-CreateTestDatabases |

---

## `database-admin/migration/` — Migration toolkit

| Subfolder | Contents |
|-----------|----------|
| `sql/` | Get-MigrationRiskAssessment, Get-DeprecatedFeaturesInUse, Get-CompatibilityLevelAudit, Generate-LoginScript, Generate-AgentJobScript, and other migration assessment and DDL generator SQL scripts |
| `powershell/` | Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript, Generate-LinkedServerScript, Generate-RestoreWithMoveScript, Invoke-MigrationExport, Invoke-PreMigrationAssessment, Export-MigrationBaseline |

---

## `database-admin/collectors/` — Scheduled monitoring

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

## `web-ui/` — Browser UI and wrappers

| Item | Purpose |
|------|---------|
| `web-ui/Start-WebUi.ps1` | Local web interface for browsing scripts and visualising CSV output |
| `web-ui/Restart-WebUi.ps1` | Restarts the UI server |
| `web-ui/Generate-ScriptIndex.ps1` | Regenerates `docs/script-index.md` from script headers |
| `web-ui/wrappers/` | Thin PS wrappers — one per SQL script; **presence here is what makes a script appear in the web UI** |

### `web-ui/wrappers/` — Thin PS wrappers

One wrapper per SQL script. Each wrapper resolves the repo root (three levels up), locates its matching `.sql` file, and delegates to `tools/local-sql/Invoke-RepoSql.ps1`. Categories mirror `database-admin/sql-scripts/` and `database-admin/migration/sql/`.

| Folder | Wraps |
|--------|-------|
| `wrappers/monitoring/` | All `sql-scripts/monitoring/` scripts |
| `wrappers/performance/` | All `sql-scripts/performance/` scripts |
| `wrappers/backups/` | All `sql-scripts/backups/` scripts |
| `wrappers/security/` | All `sql-scripts/security/` scripts |
| `wrappers/migration/` | All `migration/sql/` Get-* scripts |
| `wrappers/ha-dr/` | All `sql-scripts/ha-dr/` scripts |
| `wrappers/maintenance/` | `sql-scripts/maintenance/` Get-* scripts |

---

## `tools/` — Repo utilities

| Folder | Contents |
|--------|----------|
| `tools/local-sql/` | `Invoke-RepoSql.ps1` (core runner), `Test-SqlConnectivity.ps1`, `Set-SqlConnection.ps1`, `Install-Prerequisites.ps1` |
| `tools/triage/` | `Show-RepoOverview.ps1`, `Find-UsefulScript.ps1`, `Quick-TaskRouter.ps1` |
| `tools/scaffolding/` | `New-MultiServerScript.ps1` — wraps any SQL or PS in a multi-server foreach loop |
| `tools/maintenance/` | `Clear-OutputFiles.ps1`, `update-powershell.ps1` |

---

## `database-admin/change-templates/` — Change management

SQL templates, change orders, checklists, and runbooks for planned DBA work.

| Item | Contents |
|------|----------|
| `*.sql` (root) | SQL templates for CDC, TDE, AG, mirroring, DBCC, statistics, patching |
| `change-orders/` | CAB-ready change order documents for AlwaysOn failover, server migration, SQL upgrade |
| `checklists/` | Step-by-step checklists for AG migration, DR failover, server replacement, version upgrade |
| `runbooks/` | Full runbooks for standalone migration, AG cluster migration, OS upgrade, edition change, version upgrade |
| `rollback/` | Migration rollback playbook with binary trigger criteria and decision ownership |

---

## Adding new content

**New SQL script:** `database-admin/sql-scripts/<category>/Get-Something.sql` — use the standard header from `CLAUDE.md`.

**New PS wrapper:** Copy any existing wrapper from `web-ui/wrappers/<category>/`, update the SQL path and description. Use `$PSScriptRoot '..\..\..'` — wrappers are three levels from root. The wrapper must exist for the script to appear in the web UI.

**New unique PS script:** Add to `database-admin/powershell-scripts/<subfolder>/`. Use `$PSScriptRoot '..\..\..'` to resolve the repo root.

**New collector:** Follow the pattern in any existing `database-admin/collectors/<name>/` — one `.sql`, one `Collect-*.ps1`, one `README.md` with SQL Agent T-SQL.
