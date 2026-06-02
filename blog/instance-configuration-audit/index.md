---
title: "Script: SQL Server Instance Configuration Audit"
slug: sql-server-instance-configuration-audit
published: 
published_url: 
status: draft
category: monitoring
tags: [configuration, audit, security, memory, maxdop, instance]
scripts:
  - sql/monitoring/Get-InstanceConfigurationScore.sql
  - powershell/reporting/Get-InstanceConfigurationScore.ps1
seo_keyphrase: SQL Server configuration audit
seo_title: "SQL Server Instance Configuration Audit — 16-Point Scorecard"
seo_description: Run a 16-point SQL Server configuration audit covering memory, security, backups, DBCC, parallelism, and database settings. PASS/WARN/FAIL output with fix commands. (161 chars — trim 1)
screenshots_needed:
  - Get-InstanceConfigurationScore output showing FAIL and WARN rows sorted by severity with finding and recommendation columns
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Instance Configuration Audit

When you take ownership of a SQL Server instance you didn't build — a migration handover, a new client, a newly inherited production environment — you need to know quickly what's been misconfigured, what's missing, and what's a genuine risk. The alternative is discovering problems one by one, after they cause pain.

This script runs 16 configuration checks covering memory, security, backups, data integrity, parallelism, database settings, and storage. Every finding returns a status (`PASS`, `WARN`, or `FAIL`), a description of what was found, and the exact SQL command to fix it.

## The problem

SQL Server ships with a handful of defaults that are genuinely bad for production:
- `max server memory` defaults to 2,147,483,647 MB (unlimited) — SQL Server can consume all available RAM and starve the OS
- `cost threshold for parallelism` defaults to 5 — nearly every query goes parallel unnecessarily on modern hardware
- `backup compression default` is off — backups are slower and larger than they need to be

Other settings drift into bad states over time: `AUTO_SHRINK` gets turned on by someone trying to reclaim disk space, `xp_cmdshell` gets enabled for a one-off script and never turned back off, `sa` login stays enabled from a default install.

A weekly configuration check catches drift before it becomes a crisis.

## The script

```sql
-- Excerpt — shows the check structure. Full script: sql/monitoring/Get-InstanceConfigurationScore.sql
SELECT
    sort_order,
    category,
    check_name,
    weight,
    status,
    finding,
    recommendation
FROM ( ... ) checks
ORDER BY
    CASE status WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END,
    CASE weight WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
    sort_order;
```

## How to run it from the repo

```powershell
# Run the configuration audit — output sorted by severity
.\run.ps1 Get-InstanceConfigurationScore

# Save to CSV for documentation or comparison
.\run.ps1 Get-InstanceConfigurationScore -OutputFormat Csv

# Against a remote instance
.\run.ps1 Get-InstanceConfigurationScore -ServerInstance MYSERVER\INST01 -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `category` | Grouping: Memory, Security, Backup, Integrity, Parallelism, Database Settings, Storage, Compatibility, Dependencies |
| `check_name` | Short name for the specific check |
| `weight` | Priority if it fails: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` |
| `status` | `PASS` (ok), `WARN` (sub-optimal but not breaking), `FAIL` (misconfigured), `INFO` (awareness finding) |
| `finding` | Specific values found on this instance — e.g. "Max server memory: 2147483647 MB — no limit set" |
| `recommendation` | The exact SQL command to fix the finding, or "No action required" |

The output is sorted by severity first — `FAIL` rows appear before `WARN`, and within each status by weight (`CRITICAL` before `HIGH` before `MEDIUM`). The most urgent items are always at the top.

## What the 16 checks cover

### Memory
**Max server memory configured** — if still at the default of 2,147,483,647 MB (i.e. unconfigured), SQL Server will take as much RAM as it can. This starves the OS, causes paging, and can bring down the server. Recommended: leave 4 GB for the OS on servers with > 16 GB RAM.

**Optimize for ad hoc workloads** — by default, SQL Server caches a full plan for every ad-hoc query on first execution, even if it never runs again. With this option on, it caches only a stub on first execution and promotes to a full plan only if the same query runs again. Reduces plan cache bloat significantly on busy OLTP servers.

### Parallelism
**MAXDOP configured** — if `max degree of parallelism` is 0 (unlimited) on a multi-core server with more than 8 CPUs, every query that crosses the cost threshold can use every available CPU. Recommended: 4–8 for OLTP, capped to the number of logical cores per NUMA node.

**Cost threshold for parallelism** — at the default of 5, trivial OLTP queries go parallel. Most production servers should be 25–50. Raising this to 50 eliminates unnecessary parallelism on short queries without affecting large analytical queries.

### Backup
**All databases have a recent full backup** — checks `msdb.dbo.backupset` for any user database without a full backup in the last 7 days. A `FAIL` here means databases are unprotected.

**Backup compression enabled** — compression is available since SQL Server 2008 Standard and reduces backup size and duration by 60–80% on typical data. There's almost no reason not to enable it as the default.

### Integrity
**DBCC CHECKDB run within 7 days** — uses `DATABASEPROPERTYEX('LastGoodCheckDbTime')` to find databases that haven't had a successful integrity check in a week. Microsoft recommends weekly CHECKDB at minimum. A `WARN` here means corruption could have gone undetected.

**No databases offline or suspect** — a `FAIL` on this needs immediate investigation.

**Page verify set to CHECKSUM** — CHECKSUM detects I/O-related page corruption. TORN_PAGE_DETECTION only catches some corruption. NONE catches nothing. All user databases should be set to CHECKSUM.

### Security
**sa login disabled or renamed** — the `sa` account is the primary target for SQL authentication attacks. It should be disabled or renamed on every production instance.

**xp_cmdshell disabled** — `xp_cmdshell` allows anyone with EXECUTE permission (or sysadmin) to run OS commands from SQL. It should be disabled unless there's a specific, documented operational need.

### Database Settings
**AUTO_SHRINK disabled** — auto shrink causes recurring index fragmentation, file growth/shrink cycles, and I/O overhead. It should be off on every user database.

**AUTO_CLOSE disabled** — auto close unloads the database from memory when all connections leave, causing overhead on every reconnect and flushing the plan cache. Harmful on any database with regular connection activity.

### Storage
**No percentage-based autogrowth** — percent-based autogrowth (e.g. 10%) produces unpredictably large extension events on large files. Fixed-size increments are always preferable for data files.

### Compatibility
**Databases at current compat level** — databases below the instance's native compatibility level miss out on query optimiser improvements (dynamic statistics threshold, new CE versions, etc.). Worth reviewing after any SQL Server version upgrade.

### Dependencies
**Linked servers present** — `INFO` status: linked servers are a dependency and security consideration. The check surfaces them for awareness during a new instance review, not as a configuration error.

## Using the output

For each `FAIL` row: copy the `recommendation` column value and run it. These are the urgent fixes.

For each `WARN` row: review the `finding` and decide whether the recommendation is appropriate for this instance. Some WARNs are context-specific — MAXDOP settings differ for a pure OLTP box vs. a mixed analytics server.

Save the output to CSV before and after making changes to document what was fixed.

## Related scripts

- [`Get-BackupCoverage`](../backup-coverage/index.md) — drill into which specific databases lack backups
- [`Get-LastDbccCheckdb`](../dbcc-checkdb-history/index.md) — see per-database CHECKDB status
- [`Get-WeakLoginSettings`](../sysadmin-audit/index.md) — deeper security login audit

## Get the scripts

The full script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-InstanceConfigurationScore.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-InstanceConfigurationScore.sql)
- [`powershell/reporting/Get-InstanceConfigurationScore.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-InstanceConfigurationScore.ps1)

---

## SEO

**Focus keyphrase:** SQL Server configuration audit

**Meta description** (161 chars — trim 1 before publishing):  
Run a 16-point SQL Server configuration audit covering memory, security, backups, DBCC, parallelism, and database settings. PASS/WARN/FAIL output with fix commands.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `instance-config-score-output.png` | Get-InstanceConfigurationScore output showing FAIL rows for sa login enabled and xp_cmdshell, WARN for MAXDOP and cost threshold | Instance configuration audit output |
