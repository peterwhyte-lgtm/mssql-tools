# CLAUDE.md — DBA Scripts Project Guide

> Author: Peter Whyte (https://sqldba.blog)
> Last updated: 2026-05-29
> Purpose: Full project context, standards, and roadmap for Claude Code sessions.

---

## Project Overview

This is a production DBA toolkit for SQL Server. It contains diagnostic SQL scripts, PowerShell helpers, operational runbook templates, and supporting documentation. It is used for:
- Day-to-day troubleshooting and triage in production environments
- Content for the sqldba.blog DBA Scripts series
- A reference library for copy/paste work in SSMS and Azure Data Studio

The repo is category-first — every script lives under the category that matches the real-world DBA task, not under a flat file dump.

---

## Repository Structure (Full Map)

```
dba-scripts/
├── categories/
│   ├── backups-and-recovery/
│   │   ├── sql/         — backup coverage, history, restore scripts, DR readiness
│   │   └── powershell/  — backup age checks, restore generators, coverage wrappers
│   ├── configuration-and-environment/
│   │   ├── sql/         — MAXDOP, memory, jobs, linked servers, migration checklist
│   │   └── powershell/  — instance snapshots, job failure summaries, health overview
│   ├── dba-lab-scripts/
│   │   ├── sql/         — test database generation
│   │   └── powershell/  — test DB creation, cleanup, prefix-based removal
│   ├── high-availability-and-disaster-recovery/
│   │   ├── sql/         — AG replica state, AG latency and queue health
│   │   └── powershell/  — (stubs, future expansion)
│   ├── maintenance-and-reliability/
│   │   ├── sql/         — index fragmentation, TempDB, integrity checks, health views
│   │   └── powershell/  — health wrappers, TempDB usage runners
│   ├── performance-troubleshooting/
│   │   ├── sql/         — blocking, waits, long-running queries, missing indexes, I/O, CPU
│   │   └── powershell/  — blocking, wait stats, query, fragmentation wrappers
│   ├── security-and-permissions/
│   │   ├── sql/         — xp_cmdshell/CLR/DB Mail check, sysadmin audit, user permissions
│   │   └── powershell/  — (stubs, future expansion)
│   └── storage-capacity-management/
│       ├── sql/         — disk space, database sizes, log usage, growth risk
│       └── powershell/  — disk summary, growth risk, log sizing, largest folders
├── docs/
│   ├── README.md        — documentation index
│   ├── quick-start.md   — DBA triage workflow guide
│   ├── catalog.md       — full script inventory
│   ├── roadmap.md       — improvement priorities (live tracker)
│   ├── structure.md     — repo map and folder conventions
│   ├── script-standards.md — header and safety tag standards
│   ├── templates.md     — SQL and PowerShell template docs
│   └── runbook.md       — DBA runbook reference
├── helpers/
│   ├── local-sql/       — Invoke-LocalSql, Invoke-SqlFile, Test-SqlConnectivity, Invoke-RepoSql
│   ├── maintenance/     — Clear-OutputFiles, update-powershell
│   ├── scaffolding/     — Generate-NextScript, Generate-NextPowerShell
│   ├── triage/          — Find-UsefulScript, Quick-RepoCheck, Quick-TaskRouter, Show-RepoOverview
│   ├── Run-Helper.ps1   — name-based launcher for helpers
│   ├── Task-To-Script-Guide.md
│   └── README.md
├── output-files/        — CSV reports, demo data, backup review output
├── sql-templates/
│   └── operations/      — production runbook templates (TDE, CDC, AG, mirroring, etc.)
├── tools/               — repo maintenance tools (header validator, rename/cleanup, restructure)
├── run.ps1              — top-level launcher alias
└── README.md            — repo root orientation
```

---

## All Scripts — Full Inventory

### Backups and Recovery (`categories/backups-and-recovery/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Generate-BackupScript.sql | Generate full backup scripts for all user DBs (SSMS review) | Read-only | Low |
| Generate-RestoreScript.sql | Generate restore scripts for DR and migration | Read-only | Low |
| Get-BackupRestoreCompletionTime.sql | Monitor active backup/restore ops with ETA | Read-only | Low |
| Get-BackupRestoreDurationEstimate.sql | Analyze backup throughput metrics from msdb | Read-only | Low |
| Get-DatabaseBackupHistory.sql | Review 2-month backup history with timing and sizing | Read-only | Low |
| Get-LastDatabaseBackupTimes.sql | Latest backup timestamp per type (Full/Diff/Log) per DB | Read-only | Low |
| Get-BackupCoverage.sql | Review recent backup coverage with types, sizes, last completion | Read-only | Low |

### Configuration and Environment (`categories/configuration-and-environment/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Get-LinkedServerAndJobInventory.sql | Inventory logins, linked servers, SQL Agent jobs for migration | Read-only | Low |
| Get-MaxdopConfiguration.sql | Check MAXDOP settings and CPU topology | Read-only | Low |
| Get-MemoryConfiguration.sql | Review min/max server memory and physical memory status | Read-only | Low |
| Get-MemoryConfigurationAndUsage.sql | Configured limits and current process memory allocation | Read-only | Low |
| Get-MigrationChecklist.sql | Pre-migration validation checklist (backups, compatibility, jobs) | Read-only | Low |
| Get-SqlAgentJobFailureSummary.sql | Recent SQL Agent job failures with steps and errors | Read-only | Low |
| Get-SqlAgentJobOverview.sql | All jobs with enabled state, owner, last run outcome | Read-only | Low |
| Get-SqlServerCpuTopologyAndSchedulerDetails.sql | CPU topology, NUMA layout, scheduler details | Read-only | Low |
| Get-InstanceConfigurationSnapshot.sql | Quick instance configuration baseline and audit | Read-only | Low |
| Get-ServicesInformation.sql | SQL Server service state, startup type, service account | Read-only | Low |
| Get-VersionAndEdition.sql | Instance version, edition, cluster status, patch level | Read-only | Low |

### DBA Lab Scripts (`categories/dba-lab-scripts/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| New-TestDatabases.sql | Create multiple test DBs with randomized names for lab/migration | Creates objects | High |

### High Availability and Disaster Recovery (`categories/high-availability-and-disaster-recovery/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Get-AvailabilityGroupLatency.sql | AG replica synchronization timing, queue health, replication rates | Read-only | Low |
| Get-AvailabilityGroupReplicaState.sql | AG replica health, connection state, sync status for failover | Read-only | Low |

### Maintenance and Reliability (`categories/maintenance-and-reliability/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Get-DatabaseGrowthEvents.sql | Recent database and log file autogrowth events from default trace | Read-only | Low |
| Get-DatabaseIntegrityChecks.sql | Pre-check DB readiness and config for integrity validation runs | Read-only | Low |
| Get-IndexFragmentation.sql | Index fragmentation across user tables for maintenance planning | Read-only | Low |
| Get-TempdbUsage.sql | TempDB file sizes and usage for capacity checks | Read-only | Low |
| Get-TempdbHotspots.sql | Large TempDB consumers and growth pressure with allocation stats | Read-only | Low |
| Get-DatabaseHealth.sql | Health and sizing posture of user databases | Read-only | Low |

### Performance Troubleshooting (`categories/performance-troubleshooting/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Get-BlockingSessions.sql | Current blocking sessions with blocked requests, waits, timing | Read-only | Low |
| Get-DeadlockSummary.sql | Recent deadlock events from system_health XE session | Read-only | Low |
| Get-LongRunningQueries.sql | Long-running queries with wait state, CPU, elapsed time | Read-only | Low |
| Get-MissingIndexes.sql | Missing index candidates from DMVs for performance tuning | Read-only | Low |
| Get-TopCpuQueries.sql | Top 20 CPU-consuming queries with execution counts and timing | Read-only | Low |
| Get-WorkerThreadsAndActiveSessions.sql | Worker thread count and active sessions with CPU and elapsed time | Read-only | Low |
| Get-BlockingSummary.sql | Blocking summary starter template | Read-only | Low |
| Get-DatabaseIoUsage.sql | Database I/O totals for read/write troubleshooting | Read-only | Low |
| Get-IndexFragmentationAcrossDatabases.sql | Index fragmentation across all user databases | Read-only | Low |
| Get-WaitStatistics.sql | Instance-level wait statistics for performance triage | Read-only | Low |

### Security and Permissions (`categories/security-and-permissions/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Get-DatabaseMailAndXpCmdShell.sql | Review DB Mail, xp_cmdshell, and CLR enabled status | Read-only | Low |
| Get-SysadminMembers.sql | Members of sysadmin fixed server role for audits | Read-only | Low |
| Get-UserPermissionsAudit.sql | SQL Server logins and their types for permission reviews | Read-only | Low |

### Storage Capacity Management (`categories/storage-capacity-management/sql/`)

| Script | Purpose | Safe | Impact |
|--------|---------|------|--------|
| Get-DatabaseGrowthRisk.sql | Growth-risk summary for storage and capacity planning | Read-only | Low |
| Get-DatabaseSizesAndFreeSpace.sql | Database size and free-space for all online user databases | Read-only | Low |
| Get-DiskSpace.sql | Volume-level disk space and free-space percentages on the host | Read-only | Low |
| Get-TransactionLogSizeAndUsage.sql | Transaction log size, used space, and percent used per database | Read-only | Low |

### SQL Templates (`sql-templates/operations/`)

| Template | Purpose | Safe | Impact |
|---------|---------|------|--------|
| Update-Statistics-Template.sql | Runbook for controlled statistics updates | Writes | Medium |
| Configure-Cdc-Template.sql | Runbook for enabling Change Data Capture | Creates objects | High |
| Configure-Tde-Template.sql | Runbook for enabling Transparent Data Encryption | Creates objects | High |
| Pre-OSUpgrade-Readiness.sql | Pre-OS upgrade checklist and readiness validation | Read-only | Low |
| Configure-AlwaysOn-AvailabilityGroup-Template.sql | AG setup and validation runbook | Creates objects | High |
| Configure-Mirroring-Template.sql | Database mirroring setup and validation | Creates objects | High |
| Database-Consistency-Check-Template.sql | Repeatable DBCC CHECKDB validation template | Read-only | Low |
| Recompile-Procedure-Template.sql | Refresh execution plan for a stored procedure | Writes | Low |
| Restore-Database-NoRecovery-Template.sql | Controlled restore for DR and secondary recovery | Writes | High |

---

## Coding Standards

### SQL Script Header (required on every script)

```sql
/*
Script Name : <short descriptive name>
Category    : <category folder name>
Purpose     : <one-line purpose statement>
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only | Writes data | Creates objects
Impact      : Low | Medium | High
Requires    : <permissions — e.g. VIEW SERVER STATE, sysadmin, db_datareader>
*/
SET NOCOUNT ON;
```

### Safety Annotations (inline, beside query blocks)

```sql
-- SAFE:ReadOnly
-- IMPACT:Low
-- IMPACT:Medium       -- large scans or multi-DB loops
-- IMPACT:High         -- use with caution in production
-- WARNING:            -- destructive, irreversible, or long-running
-- REQUIRES:           -- non-obvious permission note
```

### Code Hygiene Rules

- `SET NOCOUNT ON;` at the top of every script — suppresses DONE_IN_PROC row-count messages
- No `WITH (NOLOCK)` — returns dirty/uncommitted data; removed from all scripts
- No deprecated system tables:
  - `sys.sysprocesses` → use `sys.dm_exec_sessions` / `sys.dm_exec_requests`
  - `DBCC INPUTBUFFER` → use `sys.dm_exec_input_buffer`
- No unnecessary temp tables — prefer table variables or direct query results
- No cursors — use set-based queries
- `BEGIN TRY ... END TRY / BEGIN CATCH ... END CATCH` on operations that can fail (msdb queries, cross-DB access, DR readiness checks)
- Suggest indexes only as comments — never CREATE INDEX in diagnostic scripts
- Keep scripts SSMS-paste friendly — no magic variables that require external tooling

### PowerShell Script Conventions

- Scripts invoke SQL files via `Invoke-SqlFile.ps1` or `Invoke-LocalSql.ps1` from `helpers/local-sql/`
- Output is written to `output-files/` as CSV where applicable
- Naming: `Verb-Noun.ps1` (PowerShell verb-noun convention)
- No hard-coded server names — use `-ServerInstance` parameter pattern

---

## Phase Progress Tracker

### Phase 1 — Repo Structure and Navigation ✅ COMPLETE

| Task | Status |
|------|--------|
| Category-first layout under `categories/` | Done |
| SQL / PowerShell split per category | Done |
| Helper layer (`helpers/triage`, `helpers/local-sql`, etc.) | Done |
| Output path (`output-files/`) | Done |
| Top-level launcher (`run.ps1`, `helpers/Run-Helper.ps1`) | Done |
| Top-level docs (README, quick-start, catalog, structure) | Done |
| SQL templates in `sql-templates/operations/` | Done |

**Phase 1 score: 9/10 structure, 8/10 navigation, 8/10 helper usability**

---

### Phase 2 — Standards and Script Quality ✅ COMPLETE

| Task | Status | Notes |
|------|--------|-------|
| `docs/script-standards.md` created | Done | — |
| Standard headers on all 42 SQL scripts | Done | Script Name, Category, Purpose, Author, Safe, Impact, Requires |
| `SET NOCOUNT ON` on all 42 SQL scripts | Done | — |
| Safety annotations on all 42 SQL scripts | Done | `SAFE:ReadOnly`, `IMPACT:Low/Medium/High`, `WARNING:` as applicable |
| `WITH (NOLOCK)` removed | Done | None found across all scripts |
| Deprecated DMVs replaced | Done | No `sys.sysprocesses` or `DBCC INPUTBUFFER` found |
| `Get-DatabaseMailAndXpCmdShell.sql` fixed | Done | Replaced `sp_configure`+`RECONFIGURE` (write) with `sys.configurations` (read-only) |
| `Get-DatabaseGrowthEvents.sql` fixed | Done | Fixed trace path: `sys.traces WHERE is_default=1` instead of `sys.configurations` |
| `New-TestDatabases.sql` corrected | Done | Safety fixed to `WARNING`, `IMPACT:High` — linter had incorrectly marked it ReadOnly/Low |
| `TRY...CATCH` added to error-prone scripts | Done | Already present in `New-TestDatabases.sql`; other scripts are read-only DMV queries |

**Phase 2 score: 9/10**

---

### Phase 3 — Per-Script Documentation 📋 NOT STARTED

Every SQL script needs a companion markdown doc at `docs/scripts/<category>/<script-name>.md` with:

- Purpose and when to use it
- SQL Server version requirements
- Required permissions
- Parameters or variables to adjust
- Example output (table with sample rows)
- How to interpret the results
- Any caveats or warnings

**Target: 42 SQL scripts + 9 SQL templates = 51 markdown docs**

Priority order for documentation:
1. `performance-troubleshooting/` — highest day-to-day use
2. `backups-and-recovery/` — DR-critical
3. `security-and-permissions/` — compliance and audit use
4. `configuration-and-environment/` — migration and baseline use
5. `maintenance-and-reliability/` — scheduled maintenance use
6. `storage-capacity-management/` — capacity planning use
7. `high-availability-and-disaster-recovery/` — AG-specific use
8. `dba-lab-scripts/` — lab use only
9. `sql-templates/operations/` — runbook docs

**Phase 3 score: 4/10 (top-level docs exist; per-script notes missing)**

---

### Phase 4 — CI Pipeline 🔲 NOT STARTED

Target: GitHub Actions workflows that run on every pull request.

#### CI Pipeline Architecture

```
PR / Push
  └── SQL Lint (SQLFluff)
        ├── Pass → Markdown Lint (markdownlint)
        │           ├── Pass → Link Checker (markdown-link-check)
        │           │           ├── Pass → Approve / Merge
        │           │           └── Fail → Block PR + annotate
        │           └── Fail → Block PR + annotate
        └── Fail → Block PR + annotate
```

#### Files to create

| File | Purpose |
|------|---------|
| `.github/workflows/sql-lint.yml` | SQLFluff lint on all `.sql` files |
| `.github/workflows/markdown-lint.yml` | markdownlint on all `.md` files |
| `.github/workflows/link-check.yml` | markdown-link-check on docs |
| `.sqlfluff` | SQLFluff config (dialect: tsql, rules) |
| `.markdownlint.json` | markdownlint config |

**Phase 4 score: 0/10 — no CI in place**

---

## Full Prioritized Roadmap

Listed in execution order. Each item maps to a phase above.

### Immediate (Phase 2 continuation)

1. **Apply standard headers to all remaining SQL scripts**
   - All 42 scripts in `categories/*/sql/`
   - Use the header template from `docs/script-standards.md`
   - Add `SET NOCOUNT ON;` and safety annotations

2. **Remove `WITH (NOLOCK)` from all scripts**
   - Scan all `.sql` files and strip the hint
   - Add a comment explaining why if the original intent was to avoid blocking

3. **Replace deprecated references**
   - `sys.sysprocesses` → `sys.dm_exec_sessions` / `sys.dm_exec_requests`
   - `DBCC INPUTBUFFER` → `sys.dm_exec_input_buffer`
   - Check all scripts in `performance-troubleshooting/` and `configuration-and-environment/`

4. **Add `TRY...CATCH` to high-risk scripts**
   - `Get-BackupCoverage.sql` — msdb cross-DB query
   - `Get-DatabaseBackupHistory.sql` — large msdb scan
   - `New-TestDatabases.sql` — creates databases
   - Any script using `OPENQUERY`, linked servers, or cross-DB joins

### Short Term (Phase 3 — documentation)

5. **Create per-script markdown docs for performance-troubleshooting category**
   - Priority: `Get-BlockingSessions`, `Get-LongRunningQueries`, `Get-WaitStatistics`, `Get-DeadlockSummary`, `Get-TopCpuQueries`, `Get-MissingIndexes`
   - Place in `docs/scripts/performance-troubleshooting/`

6. **Create per-script markdown docs for backups-and-recovery category**
   - Priority: `Get-BackupCoverage`, `Get-LastDatabaseBackupTimes`, `Get-BackupRestoreDurationEstimate`

7. **Create per-script markdown docs for security-and-permissions category**
   - Priority: `Get-DatabaseMailAndXpCmdShell`, `Get-SysadminMembers`, `Get-UserPermissionsAudit`

8. **Create per-script markdown docs for remaining categories**
   - Work through configuration, maintenance, storage, HA/DR, lab in that order

9. **Update `docs/catalog.md` to link to per-script docs**
   - Each row in the catalog table should link to the script's markdown doc

### Medium Term (Phase 4 — CI)

10. **Create `.sqlfluff` config for T-SQL**
    - Dialect: `tsql`
    - Rules: require uppercase keywords, consistent spacing, no trailing whitespace

11. **Create `.github/workflows/sql-lint.yml`**
    - Trigger: PR to main
    - Steps: checkout → install SQLFluff → run on `categories/**/*.sql` and `sql-templates/**/*.sql`

12. **Create `.github/workflows/markdown-lint.yml`**
    - Trigger: PR to main
    - Steps: checkout → install markdownlint-cli → run on `docs/**/*.md` and all `README.md` files

13. **Create `.github/workflows/link-check.yml`**
    - Trigger: PR to main
    - Steps: checkout → install markdown-link-check → validate all doc links

### Longer Term (Phase 5 — automation and ops improvement)

14. **Improve `sql-templates/operations` quality**
    - Make templates more production-ready (ServiceNow-style change order format)
    - Add rollback sections to every high-impact template
    - Add prerequisite checklist sections

15. **Expand PowerShell wrappers for HA/DR and security categories**
    - `Get-AvailabilityGroupLatency.ps1` — AG monitoring wrapper
    - `Get-SysadminMembers.ps1` — security audit wrapper
    - `Get-UserPermissionsAudit.ps1` — permissions audit wrapper

16. **Add dbatools-based automation scripts**
    - `Invoke-BackupAllDatabases-dbatools.ps1` — using `Backup-DbaDatabase`
    - `Test-DbaLastBackup.ps1` — backup restore test automation
    - `Get-DbaWaitStatistics.ps1` — wait stats via dbatools

17. **Add `output-files/` structured report templates**
    - Health check report template (CSV + summary)
    - Backup audit report template
    - Migration readiness report template

18. **Consider per-category PowerShell integration script**
    - A single `Run-CategoryCheck.ps1` that accepts a category name and runs all scripts in it

---

## Key Standards Reference

### Naming Conventions

- SQL scripts: `Verb-Noun.sql` (PascalCase, matches the diagnostic action)
- PowerShell scripts: `Verb-Noun.ps1` (standard PowerShell verb-noun)
- Folder names: `lowercase-hyphenated`
- No spaces in any filename

### SQL Version Targets

- Minimum: SQL Server 2016 (SP2+)
- Where possible, note if a script requires 2017+ or 2019+ (e.g. for `sys.dm_exec_input_buffer`, `STRING_AGG`)

### Permissions Reference (common)

| Permission | Used for |
|-----------|---------|
| `VIEW SERVER STATE` | DMV queries (sessions, requests, wait stats) |
| `sysadmin` | xp_cmdshell checks, some configuration reads |
| `db_datareader` on msdb | Backup history queries |
| `ALTER DATABASE` | TDE, CDC, AG templates |
| `dbcreator` | Test database creation |

---

## Blog and Content Alignment

Scripts in this repo feed the sqldba.blog DBA Scripts series. When adding or updating scripts:
- Prioritize scripts that have real production troubleshooting value
- Keep SSMS paste-and-run as the primary UX
- Write headers and comments as if the reader is a mid-level production DBA
- Avoid over-engineering — the goal is fast, safe, readable diagnostics

---

## Quick Commands

```powershell
# Show full repo overview
.\run.ps1 Show-RepoOverview

# Run a specific script by name
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-LongRunningQueries
.\run.ps1 Get-BlockingSessions

# Test connectivity before running
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance . -Database master

# Run a SQL file directly
.\helpers\local-sql\Invoke-SqlFile.ps1 -FilePath .\categories\performance-troubleshooting\sql\Get-WaitStatistics.sql

# Find a script by keyword
.\helpers\triage\Find-UsefulScript.ps1 -Keyword blocking

# Generate a new SQL script scaffold
.\helpers\scaffolding\Generate-NextScript.ps1

# Clean up output files
.\helpers\maintenance\Clear-OutputFiles.ps1
```

---

## Current Overall Score

| Area | Score | Notes |
|------|------:|-------|
| Repository structure | 9/10 | Category-first, SQL/PowerShell split, helpers — solid |
| Navigation and discoverability | 8/10 | Good entry points; per-script discovery still manual |
| Output collection | 8/10 | CSV reports under `output-files/` working |
| Helper usability | 8/10 | Launcher and helpers are clean and usable |
| Script standards and headers | 9/10 | All 42 SQL scripts have full headers, SET NOCOUNT ON, and safety annotations |
| Per-script documentation | 4/10 | Top-level docs good; per-script markdown missing |
| CI and quality gates | 0/10 | No SQL linter, Markdown lint, or link checks yet |
| PowerShell wrapper coverage | 6/10 | Good for core categories; HA/DR and security thin |
| Template quality | 7/10 | Good coverage; rollback sections and change-order format pending |

**Composite: ~7.5/10 — Phase 2 complete, Phase 3 (per-script docs) is next**
