# mssql-tools repo structure

This document describes the current folder layout and the purpose of each area.

---

## Top-level layout

```text
sql/            SQL scripts (read-only, SSMS-ready, single-result-set)
powershell/     PowerShell orchestrators, automation, collectors, migration tools
web-ui/         Browser UI + thin PS wrappers (one per SQL script)
tools/          Repo utilities: SQL runner, triage, scaffolding, maintenance
docs/           Documentation: structure, roadmap, runbooks, quick-start
docs/ops/       Change orders, runbooks, checklists, rollback playbooks
blog/           Draft blog posts for sqldba.blog
tests/          Pester test suite
output-files/   Generated output (gitignored — CSVs, healthcheck folders, reports)
```

---

## `sql/` — SQL scripts

All SQL scripts are single-result-set, read-only, and SSMS paste-and-run compatible. Every script has a standard header with `Script Name`, `Purpose`, `Author`, `Safe`, `Impact`, and `Requires`.

| Category | Contents |
|----------|----------|
| `monitoring/` | Instance health, memory, MAXDOP, jobs, TempDB, DBCC, suspect pages, disk, config |
| `performance/` | Waits, blocking, long queries, missing indexes, I/O, plan cache, active requests |
| `backups/` | Coverage, history, DR estimates, restore generation, encryption status |
| `security/` | Roles, permissions, orphans, weak logins, surface area, linked server security |
| `ha-dr/` | AG replica state, AG latency, readable secondary usage |
| `maintenance/` | Index maintenance jobs, backup jobs, housekeeping jobs, job status |
| `lab/` | Dev/test-only scripts — blocking scenarios, test database creation |

Migration SQL scripts live separately at `sql/migration/`. See [script-catalog.md](script-catalog.md) for the full list.

---

## `powershell/` — Unique PowerShell scripts

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

## Migration toolkit

| Location | Contents |
|----------|----------|
| `sql/migration/` | Get-MigrationRiskAssessment, Get-DeprecatedFeaturesInUse, Get-CompatibilityLevelAudit, Generate-LoginScript, Generate-AgentJobScript, and other migration assessment and DDL generator SQL scripts |
| `powershell/migration/` | Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript, Generate-LinkedServerScript, Generate-RestoreWithMoveScript, Invoke-MigrationExport, Invoke-PreMigrationAssessment, Export-MigrationBaseline |

---

## `powershell/collectors/` — Scheduled monitoring

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

One wrapper per SQL script. Each wrapper resolves the repo root (three levels up), locates its matching `.sql` file, and delegates to `tools/local-sql/Invoke-RepoSql.ps1`. Categories mirror `sql/` and `sql/migration/`.

| Folder | Wraps |
|--------|-------|
| `wrappers/monitoring/` | All `monitoring/` scripts |
| `wrappers/performance/` | All `performance/` scripts |
| `wrappers/backups/` | All `backups/` scripts |
| `wrappers/security/` | All `security/` scripts |
| `wrappers/migration/` | All `migration/sql/` Get-* scripts |
| `wrappers/ha-dr/` | All `ha-dr/` scripts |
| `wrappers/maintenance/` | `maintenance/` Get-* scripts |

---

## `tools/` — Repo utilities

| Folder | Contents |
|--------|----------|
| `tools/local-sql/` | `Invoke-RepoSql.ps1` (core runner), `Test-SqlConnectivity.ps1`, `Set-SqlConnection.ps1`, `Install-Prerequisites.ps1` |
| `tools/triage/` | `Show-RepoOverview.ps1`, `Find-UsefulScript.ps1`, `Quick-TaskRouter.ps1` |
| `tools/scaffolding/` | `New-MultiServerScript.ps1` — wraps any SQL or PS in a multi-server foreach loop |
| `tools/maintenance/` | `Clear-OutputFiles.ps1`, `update-powershell.ps1` |

---

## `docs/ops/` — Change management

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

**New SQL script:** `sql/<category>/Get-Something.sql` — use the standard header from `CLAUDE.md`.

**New PS wrapper:** Copy any existing wrapper from `web-ui/wrappers/<category>/`, update the SQL path and description. Use `$PSScriptRoot '..\..\..'` — wrappers are three levels from root. The wrapper must exist for the script to appear in the web UI.

**New unique PS script:** Add to `powershell/<subfolder>/`. Use `$PSScriptRoot '..\..\..'` to resolve the repo root.

**New collector:** Follow the pattern in any existing `powershell/collectors/<name>/` — one `.sql`, one `Collect-*.ps1`, one `README.md` with SQL Agent T-SQL.
