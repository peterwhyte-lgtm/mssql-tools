---
title: "Script: SQL Server tempdb Contention and Usage Analysis"
slug: sql-server-tempdb-contention
published: 
published_url: 
status: draft
category: monitoring
tags: [tempdb, contention, performance, spills, allocation, pagelatch]
scripts:
  - sql/monitoring/Get-TempdbHotspots.sql
  - sql/monitoring/Get-TempdbUsage.sql
  - powershell/health-checks/Get-TempdbHotspots.ps1
seo_keyphrase: SQL Server tempdb contention
seo_title: "SQL Server tempdb Contention — Finding Who's Using tempdb and Why"
seo_description: Find which sessions are consuming the most tempdb space and identify whether it's from temp tables, sort spills, or row versioning. Includes allocation contention diagnosis. (176 chars — trim)
screenshots_needed:
  - Get-TempdbHotspots output showing session_id, login_name, user_objects_mb, internal_objects_mb, total_tempdb_mb, and wait_type columns
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server tempdb Contention and Usage Analysis

tempdb is one of the most contention-prone resources in SQL Server. Every instance has one, every session shares it, and it handles several different types of work simultaneously: temporary tables, sort and hash spills, row version stores for snapshot isolation, internal work tables for operations like index rebuilds. When any of these gets heavy, tempdb becomes a bottleneck for the entire instance.

Two forms of tempdb problems are common:

**Allocation page contention** — SQL Server's tempdb uses a small number of allocation pages (PFS, GAM, SGAM) to track free space. On pre-2016 instances without trace flags, or on instances with only one tempdb data file, these allocation pages become hot spots. Every session allocation serialises through them, creating `PAGELATCH_EX` or `PAGELATCH_SH` waits on those specific pages.

**Excessive space consumption** — one or more sessions consuming large amounts of tempdb space via temp tables, sort spills, or version store entries, crowding out other sessions.

## The scripts

### Get-TempdbHotspots.sql — current top tempdb consumers

```sql
SELECT
    ssu.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id)                                                          AS active_database,
    CAST(ssu.user_objects_alloc_page_count     * 8.0 / 1024 AS DECIMAL(10,2))      AS user_objects_mb,
    CAST(ssu.internal_objects_alloc_page_count * 8.0 / 1024 AS DECIMAL(10,2))      AS internal_objects_mb,
    CAST((ssu.user_objects_alloc_page_count
        + ssu.internal_objects_alloc_page_count) * 8.0 / 1024 AS DECIMAL(10,2))    AS total_tempdb_mb,
    r.wait_type,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000.0 AS DECIMAL(10,1))                AS elapsed_sec
FROM sys.dm_db_session_space_usage    AS ssu
JOIN sys.dm_exec_sessions              AS s   ON ssu.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests         AS r   ON ssu.session_id = r.session_id
WHERE ssu.session_id > 50
  AND (ssu.user_objects_alloc_page_count + ssu.internal_objects_alloc_page_count) > 0
ORDER BY total_tempdb_mb DESC;
```

## How to run it from the repo

```powershell
# Current top tempdb consumers
.\run.ps1 Get-TempdbHotspots

# File-level tempdb sizes and usage
.\run.ps1 Get-TempdbUsage

# Save for comparison over time
.\run.ps1 Get-TempdbHotspots -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `session_id` | The SQL Server session consuming tempdb space. |
| `login_name` / `host_name` / `program_name` | Who and what owns this session. |
| `active_database` | Which database the session is currently working in. |
| `user_objects_mb` | Tempdb space used by explicit temporary objects: `#temp` tables, `##global_temp` tables, table variables materialised in tempdb. |
| `internal_objects_mb` | Tempdb space used by internal objects: sort worktables (spills), hash join worktables, cursor spool pages, XML variables. If this is large, the session is spilling sort or hash operations to disk. |
| `total_tempdb_mb` | Total tempdb space for this session. |
| `wait_type` | What the session is currently waiting for. `IO_COMPLETION` alongside high `internal_objects_mb` confirms sort spills are active. `PAGELATCH_EX` on tempdb allocation pages confirms allocation contention. |
| `elapsed_sec` | How long the session has been running its current request. |

## What `user_objects_mb` vs `internal_objects_mb` tells you

**High `user_objects_mb`** — the session has created large temp tables. Could be a legitimate ETL process staging data, or a poorly written query creating massive temp table copies of data that don't need to be stored. Check the session's current statement.

**High `internal_objects_mb`** — the session is spilling sorts or hash joins to disk. This means it didn't get enough memory grant to complete the operation in-memory. Root causes: stale statistics producing underestimated memory grants, missing indexes causing large scan-based operations, or general memory pressure. See also: `RESOURCE_SEMAPHORE` in wait stats.

## Diagnosing allocation page contention

Allocation contention shows up as `PAGELATCH_EX` or `PAGELATCH_SH` waits on tempdb pages with `wait_resource` values like `2:1:1` (tempdb, file 1, page 1 — the PFS page). Check the wait statistics script:

```powershell
.\run.ps1 Get-WaitStatistics
```

If `PAGELATCH_EX` or `PAGELATCH_SH` is elevated and the wait resource points to tempdb pages 1, 2, or 3 (PFS, GAM, SGAM), this is allocation contention.

**Fixes for allocation contention:**

1. **Multiple tempdb data files** — the most effective fix. SQL Server 2016+ recommends one tempdb data file per logical core, up to 8. Each file has its own allocation pages, spreading contention across files:

```sql
-- Add tempdb data files (run in tempdb context)
-- Adjust path and size to match your existing tempdb configuration
ALTER DATABASE tempdb ADD FILE (
    NAME = N'tempdev2',
    FILENAME = N'D:\tempdb\tempdev2.ndf',
    SIZE = 8192MB,
    FILEGROWTH = 512MB
);
-- Repeat for tempdev3, tempdev4... up to the number of logical cores (max 8)
```

All tempdb data files should be the same size. SQL Server uses proportional fill across files, so equal sizes spread allocations evenly.

2. **Trace flags 1117 and 1118** — on SQL Server 2014 and earlier, these trace flags are needed to enable uniform extent allocation and auto-grow behaviour that reduces allocation page contention. On SQL Server 2016+, this behaviour is the default for tempdb and the trace flags are no longer needed.

## Version store contention (RCSI)

If any databases have Read Committed Snapshot Isolation (RCSI) enabled, SQL Server maintains a version store in tempdb. Every modified row generates a version entry. Heavy update/delete workloads on RCSI databases can consume significant tempdb space.

Check version store size:

```sql
SELECT
    SUM(version_store_reserved_page_count) * 8 / 1024   AS version_store_mb
FROM sys.dm_db_file_space_usage
WHERE database_id = 2;
```

A version store above a few hundred MB means long-running read transactions are holding version chains open. Find them:

```sql
SELECT
    transaction_id,
    elapsed_time_seconds,
    transaction_sequence_num
FROM sys.dm_tran_active_snapshot_database_transactions
ORDER BY elapsed_time_seconds DESC;
```

The transactions with the highest `elapsed_time_seconds` are holding the oldest version rows. Terminating very long-running read transactions (or preventing them from running during heavy write periods) reduces version store growth.

## tempdb configuration best practices

Check current tempdb configuration:

```powershell
.\run.ps1 Get-TempdbUsage
```

The output shows file count, file sizes, and current space usage. Key things to verify:

- **File count**: one data file per logical core, up to 8. Check current CPU count: `SELECT cpu_count FROM sys.dm_os_sys_info`.
- **File sizes**: all data files should be the same size. Unequal sizes cause proportional fill to favour the larger file.
- **Log file**: tempdb should have one log file. It doesn't benefit from multiple log files.
- **Location**: tempdb should be on fast, dedicated storage — separate from production data and log files.

## Related scripts

- [`Get-WaitStatistics`](../wait-statistics/index.md) — `PAGELATCH_EX` on tempdb pages appears here; `IO_COMPLETION` high means sort spills
- [`Get-MissingIndexes`](../missing-indexes/index.md) — add indexes to eliminate sort spills from missing index scans
- [`Get-StatisticsHealth`](../statistics-health/index.md) — stale stats cause under-estimated memory grants leading to spills

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-TempdbHotspots.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-TempdbHotspots.sql)
- [`sql/monitoring/Get-TempdbUsage.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-TempdbUsage.sql)

---

## SEO

**Focus keyphrase:** SQL Server tempdb contention

**Meta description** (trim to 160 before publishing):  
Find which sessions are consuming the most tempdb space and identify whether it's from temp tables, sort spills, or row versioning. Includes allocation contention diagnosis.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `tempdb-hotspots-output.png` | Get-TempdbHotspots output showing sessions with high internal_objects_mb from sort spills and wait_type IO_COMPLETION | tempdb session usage by type |
