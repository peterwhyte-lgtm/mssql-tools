---
title: "Script: SQL Server DBCC CHECKDB History and Integrity Status"
slug: sql-server-dbcc-checkdb-history
published: 
published_url: 
status: draft
category: monitoring
tags: [integrity, dbcc, checkdb, suspect-pages, corruption, maintenance]
scripts:
  - sql/monitoring/Get-LastDbccCheckdb.sql
  - sql/monitoring/Get-DatabaseIntegrityChecks.sql
  - sql/monitoring/Get-SuspectPages.sql
  - powershell/health-checks/Get-LastDbccCheckdb.ps1
  - powershell/health-checks/Get-DatabaseIntegrityChecks.ps1
  - powershell/health-checks/Get-SuspectPages.ps1
seo_keyphrase: SQL Server DBCC CHECKDB history
seo_title: "SQL Server DBCC CHECKDB — When Did Each Database Last Run?"
seo_description: Check when each SQL Server database last had a successful DBCC CHECKDB. Includes suspect page detection and what to do when corruption is found. (148 chars)
screenshots_needed:
  - Get-LastDbccCheckdb output showing database_name, last_good_checkdb, days_since_checkdb, and checkdb_status columns with STALE and NEVER_RUN rows visible
  - Get-SuspectPages output showing a suspect page entry (or empty result showing no pages — either is useful)
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server DBCC CHECKDB History and Integrity Status

`DBCC CHECKDB` is the only way to verify that a SQL Server database is physically consistent — that no pages are corrupted, torn, or mislinked. Microsoft recommends running it at least weekly on every database. Many production environments don't.

When corruption goes undetected, it compounds. A corrupted data page becomes a corrupted index, becomes a corrupted table, becomes an unrestorable backup containing months of compounding damage. Detecting corruption early — ideally within days — keeps the repair options open.

## The problem

Most environments have a maintenance job that runs DBCC CHECKDB. Whether that job is running successfully on every database is a different question. A database added recently might not be in the maintenance plan. A job might be failing silently. A database might have grown large enough that CHECKDB is timing out or being killed.

`DATABASEPROPERTYEX(dbname, 'LastGoodCheckDbTime')` records the last time CHECKDB completed successfully for each database. Querying this across all databases in one pass tells you immediately which ones are overdue.

## The scripts

### Get-LastDbccCheckdb.sql — when did each database last pass CHECKDB

```sql
SELECT
    d.name                                                                  AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME)    AS last_good_checkdb,
    DATEDIFF(DAY,
        CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME),
        GETDATE())                                                           AS days_since_checkdb,
    CASE
        WHEN CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME) IS NULL
            THEN 'NEVER_RUN'
        WHEN DATEDIFF(DAY,
                CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME),
                GETDATE()) > 7
            THEN 'STALE'
        ELSE 'OK'
    END                                                                     AS checkdb_status
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY last_good_checkdb ASC;
```

### Get-SuspectPages.sql — pages flagged as corrupt

```sql
SELECT
    DB_NAME(database_id)    AS database_name,
    file_id,
    page_id,
    event_type,
    error_count,
    last_update_date
FROM msdb.dbo.suspect_pages
ORDER BY last_update_date DESC;
```

## How to run it from the repo

```powershell
# CHECKDB status for all databases
.\run.ps1 Get-LastDbccCheckdb

# Check for suspect pages in msdb
.\run.ps1 Get-SuspectPages

# Run the integrity check script (reports on CHECKDB job status and schedule)
.\run.ps1 Get-DatabaseIntegrityChecks

# Save CHECKDB status to CSV for compliance documentation
.\run.ps1 Get-LastDbccCheckdb -OutputFormat Csv
```

## Reading the output — Get-LastDbccCheckdb

| Column | What it means |
|--------|---------------|
| `database_name` | Database being checked. |
| `state_desc` | Database state. Only `ONLINE` databases run CHECKDB. `OFFLINE` or `RESTORING` databases will show NULL for `last_good_checkdb`. |
| `last_good_checkdb` | The last time DBCC CHECKDB completed successfully with no errors. `NULL` means it's never completed successfully on this instance for this database. |
| `days_since_checkdb` | How many days ago the last successful check was. `NULL` if never run. |
| `checkdb_status` | `NEVER_RUN` (most urgent), `STALE` (> 7 days), or `OK`. |

## Reading the output — Get-SuspectPages

| Column | What it means |
|--------|---------------|
| `database_name` | Database with the suspect page. |
| `file_id` | The data file ID containing the suspect page. |
| `page_id` | The specific page ID. |
| `event_type` | Type of error: 1 = 823 error (I/O failure), 2 = 824 error (logical consistency error), 3 = torn page. |
| `error_count` | How many times this page has been flagged. |
| `last_update_date` | When it was last encountered. |

A non-empty result from Get-SuspectPages is a critical finding requiring immediate investigation.

## What to do — STALE or NEVER_RUN databases

**Schedule DBCC CHECKDB.** The easiest approach is Ola Hallengren's SQL Server Maintenance Solution, which handles scheduling CHECKDB, managing job history, and skipping databases that are offline.

For manual scheduling:

```sql
-- Run CHECKDB on a specific database
DBCC CHECKDB ([YourDatabase]) WITH NO_INFOMSGS, ALL_ERRORMSGS;
```

For large databases where a full CHECKDB takes too long, options include:

**PHYSICAL_ONLY** — checks physical page structure and allocation consistency only. Much faster than a full check, but doesn't check logical consistency (index order, constraint violations):

```sql
DBCC CHECKDB ([LargeDatabase]) WITH PHYSICAL_ONLY, NO_INFOMSGS;
```

**Staggered checks** — run CHECKDB across databases on different nights of the week so no single night has the full load:

```
Monday:    User databases A–D
Tuesday:   User databases E–H
Wednesday: User databases I–N
Thursday:  User databases O–Z
Friday:    System databases + re-run anything that failed
```

**On an AG secondary** — if you have an Always On Availability Group, run CHECKDB on a secondary replica. This takes the I/O load off the primary:

```sql
-- Run this on the secondary
DBCC CHECKDB ([YourDatabase]) WITH NO_INFOMSGS;
```

The `LastGoodCheckDbTime` property reflects the result from any replica, including secondaries.

## What to do — suspect pages found

A suspect page means corruption exists. This is a critical incident.

**Do not delay.** The window for recovery options closes as time passes — transaction log backups become unavailable, backups age, and the corruption may spread as more operations fail.

**Immediate steps:**

1. **Check when the corruption first appeared.** The `last_update_date` in `msdb.dbo.suspect_pages` shows when it was last encountered. Check backup history to find the last clean backup before this date.

2. **Determine the scope.** Is it one page or many? One page in one file is likely recoverable. Many pages across multiple files may indicate storage failure.

3. **Restore from backup.** For most corruption scenarios, the correct fix is restoring from the last clean backup. If you're in FULL recovery model with regular log backups, you may be able to restore to just before the corruption appeared.

4. **As a last resort — REPAIR_ALLOW_DATA_LOSS.** DBCC CHECKDB can repair some corruption by removing damaged rows or pages:

```sql
-- Only when restoration is not an option
ALTER DATABASE [YourDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC CHECKDB ([YourDatabase]) WITH REPAIR_ALLOW_DATA_LOSS;
ALTER DATABASE [YourDatabase] SET MULTI_USER;
```

As the name says, this loses data. Use it only when restoration is genuinely not possible and data loss is preferable to downtime.

5. **Investigate the storage layer.** Page corruption usually comes from storage hardware — a failing disk, a storage controller bug, or a write cache issue. Run vendor diagnostics on the storage array. Check the Windows Event Log for I/O errors. Corruption that keeps reappearing after restore points to an unresolved storage problem.

## Running CHECKDB without a maintenance window

If your databases are large and you have no maintenance window, CHECKDB can be run during business hours on most workloads. It's not free — it generates I/O and uses CPU — but it's not blocking. It takes a snapshot view of the database when it starts and checks that, so active queries continue normally.

For databases above 500 GB where even a background CHECKDB impacts production, use `PHYSICAL_ONLY` during business hours and schedule a full `CHECKDB` during a weekend maintenance window.

## Related scripts

- [`Get-LastDbccCheckdb`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/health-checks/Get-LastDbccCheckdb.ps1) — this post's primary script
- [`Get-InstanceConfigurationScore`](../instance-configuration-audit/index.md) — includes a CHECKDB coverage check in the broader instance audit
- [`Get-BackupCoverage`](../backup-coverage/index.md) — clean backups are your first recovery tool when corruption is found

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-LastDbccCheckdb.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-LastDbccCheckdb.sql)
- [`sql/monitoring/Get-SuspectPages.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-SuspectPages.sql)
- [`sql/monitoring/Get-DatabaseIntegrityChecks.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-DatabaseIntegrityChecks.sql)

---

## SEO

**Focus keyphrase:** SQL Server DBCC CHECKDB history

**Meta description** (148 chars — target 150–160 — extend slightly before publishing):  
Check when each SQL Server database last had a successful DBCC CHECKDB. Includes suspect page detection and what to do when corruption is found.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `checkdb-history-output.png` | Get-LastDbccCheckdb output showing database_name, last_good_checkdb, days_since_checkdb, and STALE or NEVER_RUN status | DBCC CHECKDB history per database |
