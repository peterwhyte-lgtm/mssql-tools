# DBA Scripts

[![SQL Server](https://img.shields.io/badge/SQL%20Server-2016%2B-CC2927?logo=microsoftsqlserver&logoColor=white)](https://github.com/peterwhyte-lgtm/dba-scripts)
[![License](https://img.shields.io/github/license/peterwhyte-lgtm/dba-scripts)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/peterwhyte-lgtm/dba-scripts)](https://github.com/peterwhyte-lgtm/dba-scripts/commits/main)
[![Stars](https://img.shields.io/github/stars/peterwhyte-lgtm/dba-scripts?style=social)](https://github.com/peterwhyte-lgtm/dba-scripts)

A production-ready SQL Server DBA toolkit for diagnostics, monitoring, migration, and operational change management.

**Read the blog:** [sqldba.blog](https://sqldba.blog) — each script has a companion post with real-world context.

---

## What's in the box

- **Paste-and-run SQL** — DMV queries for waits, blocking, memory, storage, jobs, AG health, and more. All read-only, all safe for production.
- **PowerShell orchestration** — run scripts at scale, export CSVs, schedule collection, and automate health checks.
- **Health check workflow** — one command collects 22 scripts against any instance and surfaces CRITICAL/WARNING/INFO findings.
- **Assessment report** — generates a scored markdown report suitable for a client handover or ownership review.
- **Migration toolkit** — pre-migration risk assessment, baseline capture, checklists, CAB-ready change orders, and a rollback playbook.
- **Operational templates** — change orders, execution checklists, and rollback procedures for version upgrades, AG failovers, and server replacements.

---

## Table of contents

- [Quick start](#quick-start)
- [Health check workflow](#health-check-workflow)
- [Repository structure](#repository-structure)
- [Key scripts](#key-scripts)
- [Migration toolkit](#migration-toolkit)
- [Requirements](#requirements)
- [Contributing](#contributing)

---

## Quick start

```powershell
# Clone
git clone https://github.com/peterwhyte-lgtm/dba-scripts
cd dba-scripts

# Test connectivity
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance .

# Run any script by name — fuzzy match, no paths needed
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019 -OutputFormat Csv
```

The runner resolves any script by name and passes all parameters through. No need to remember folder paths.

---

## Health check workflow

Collect all monitoring data and review findings in two commands:

```powershell
# Collect 22 scripts — saves named CSVs to output-files\healthcheck\<server>-<timestamp>\
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance .

# Review findings — surfaces CRITICAL / WARNING / INFO from the collected CSVs
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

What gets flagged: offline databases, missing backups, stale DBCC CHECKDB, suspect pages, sa login enabled, unconfigured max server memory, percent-based autogrowth, job failures, I/O latency, transaction log pressure, and more.

### Assessment report

For a client handover or instance ownership review:

```powershell
# Runs the full collection + configuration scoring + findings, then writes a markdown report
.\powershell\reporting\Invoke-AssessmentReport.ps1 -ServerInstance PROD01\SQL2019 -AssessedBy "Peter Whyte"
# Output: output-files\assessment\<server>-<timestamp>.md
```

The report includes an instance score (0–100), CRITICAL/WARNING/INFO findings, database inventory, storage, and prioritised recommendations.

---

## Repository structure

```text
sql/
  monitoring/         — health, memory, MAXDOP, jobs, TempDB, DBCC, instance config
  performance/        — waits, blocking, long queries, missing indexes, I/O, active requests
  high-availability/  — AG replica state, AG latency
  backups/            — coverage, history, DR estimates, restore generation
  security/           — roles, permissions, orphans, weak logins, surface area
  migration/          — risk assessment, compat audit, login audit, deprecated features

powershell/
  reporting/          — wrappers, health check collection, assessment report
  inventory/          — storage, growth, disk, instance snapshots
  high-availability/  — AG state and latency wrappers
  health-checks/      — DBCC, suspect pages, TempDB hotspots
  backup-automation/  — backup and restore execution
  security/           — security audit wrappers
  migration/          — migration assessment, baseline capture, DDL generators

collectors/           — scheduled collectors for historical trend data (blocking, waits, I/O, AG)

sql-operations/
  change-orders/      — CAB-ready change order templates
  checklists/         — step-by-step execution checklists
  rollback/           — rollback decision criteria and procedures
  change-templates/   — SQL runbook templates (CDC, TDE, AG, statistics)
  installation/       — SQL Server installation automation
  patches/            — CU and SSMS update scripts

helpers/
  local-sql/          — Invoke-RepoSql.ps1, Set-SqlConnection.ps1, Test-SqlConnectivity.ps1
  triage/             — Show-RepoOverview.ps1, Find-UsefulScript.ps1
  scaffolding/        — Generate-NextPowerShell.ps1
```

---

## Key scripts

### Performance

| Script | Purpose |
|--------|---------|
| `Get-WaitStatistics` | Top wait types since last restart — benign waits filtered |
| `Get-BlockingChains` | Recursive blocking chain with head blocker, wait info, and optional query plans |
| `Get-LongRunningQueries` | Active queries by elapsed time with database and login |
| `Get-MissingIndexes` | DMV missing index candidates ranked by impact score |
| `Get-TopCpuQueries` | Top CPU consumers from plan cache |
| `Get-TopIoQueries` | Top I/O consumers from plan cache |
| `Get-DeadlockSummary` | Deadlock history from system health session |

### Monitoring

| Script | Purpose |
|--------|---------|
| `Get-InstanceConfigurationScore` | Scores ~16 key configuration checks as PASS/WARN/FAIL with remediation |
| `Get-DatabaseHealth` | State, recovery model, auto-shrink, page verify, compat level per database |
| `Get-TempdbUsage` | TempDB file usage, version store, free space per file |
| `Get-MemoryConfigurationAndUsage` | Max server memory vs current buffer pool and committed memory |
| `Get-MaxdopConfiguration` | MAXDOP vs CPU topology with recommended value |
| `Get-SqlAgentJobFailureSummary` | Job failures in the last 7 days |

### Backups

| Script | Purpose |
|--------|---------|
| `Get-BackupCoverage` | Full/diff/log backup status per database with backup_status flag |
| `Get-LastDatabaseBackupTimes` | Last backup time and age in hours per database |
| `Get-BackupRestoreDurationEstimate` | Estimated restore duration from backup history |

### High Availability

| Script | Purpose |
|--------|---------|
| `Get-AvailabilityGroupReplicaState` | AG replica health, sync state, connection mode |
| `Get-AvailabilityGroupLatency` | Log send/redo queue sizes and replication rates |

### Security

| Script | Purpose |
|--------|---------|
| `Get-UserPermissionsAudit` | Explicit permissions per database user |
| `Get-SysadminMembers` | sysadmin role members with login type |
| `Get-WeakLoginSettings` | SQL logins with policy or expiration disabled, sa enabled |

---

## Migration toolkit

Run against the source server before any migration:

```powershell
# Pre-migration risk assessment — saves 14 CSVs to output-files\migration\assessment\
.\powershell\migration\Invoke-PreMigrationAssessment.ps1 -ServerInstance PROD01\SQL2019

# Capture pre-migration performance baseline for post-migration comparison
.\powershell\migration\Export-MigrationBaseline.ps1 -ServerInstance PROD01\SQL2019 -Label pre

# After migration — capture post baseline and compare
.\powershell\migration\Export-MigrationBaseline.ps1 -ServerInstance PROD02\SQL2022 -Label post
```

Key assessment scripts:

| Script | Purpose |
|--------|---------|
| `Get-MigrationRiskAssessment` | HIGH/MEDIUM/INFO findings: compat gaps, bad settings, linked servers, AG membership |
| `Get-DeprecatedFeaturesInUse` | Deprecated features with active usage count since last restart |
| `Get-CompatibilityLevelAudit` | All databases with compat level, mapped SQL version, and native compat delta |
| `Get-MigrationLoginAudit` | All server principals with migration risk and per-type action guidance |

Change management templates in `sql-operations/`:

- `change-orders/` — CAB-ready approval documents for version upgrades, server migrations, AG failovers
- `checklists/` — step-by-step execution checklists for each migration type
- `rollback/migration-rollback-playbook.md` — rollback triggers, decision ownership, and procedure per migration type

---

## Requirements

- SQL Server 2016 or later
- PowerShell 5.1 or PowerShell 7+
- `Invoke-Sqlcmd` (SqlServer module) or `sqlcmd.exe` on the path
- `VIEW SERVER STATE` and `VIEW ANY DATABASE` for most scripts

```powershell
# Install the SqlServer module if not present
Install-Module -Name SqlServer -Scope CurrentUser -Force
```

---

## Running against a remote server

Set a session-level connection once and every script picks it up:

```powershell
# Windows auth
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# SQL auth
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa

# Or pass -ServerInstance directly
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and script improvements are welcome.

---

## License

[MIT](LICENSE) — use freely, attribution appreciated.

Built and maintained by [Peter Whyte](https://sqldba.blog).
