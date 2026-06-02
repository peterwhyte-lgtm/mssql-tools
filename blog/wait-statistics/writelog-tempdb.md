---
title: "WRITELOG in tempdb — SQL Server"
slug: sql-server-wait-statistics-writelog-tempdb
series: wait-statistics
series_position: 14
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, tempdb, writelog, transaction-log, spills]
seo_keyphrase: SQL Server tempdb WRITELOG
seo_title: "SQL Server WRITELOG in tempdb — tempdb Log Write Pressure"
seo_description: WRITELOG against tempdb is a separate bottleneck from production log writes. Heavy temp table use, sort spills, and row versioning all drive this wait. (151 chars)
screenshots_needed:
  - Get-WaitStatistics output showing WRITELOG prominent — with a note that this may be tempdb-driven
  - sys.dm_io_virtual_file_stats filtered to tempdb showing high avg_write_ms on the log file
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# WRITELOG — When tempdb Is the Cause

**Part of the [SQL Server Wait Statistics series](index.md)**

`WRITELOG` appears in the wait statistics output as a single wait type — it doesn't distinguish which database's transaction log is slow. On a server with multiple databases, elevated `WRITELOG` is most commonly caused by the production database's log disk. But sometimes the culprit is tempdb.

This page covers the case where `WRITELOG` is elevated and the production log disk looks fine. tempdb has its own transaction log, and heavy tempdb usage generates its own log write pressure. If tempdb's log file is on slow storage, or if tempdb is under extreme load, `WRITELOG` appears in the overall wait stats driven entirely by tempdb operations.

## How to tell whether it's tempdb or production databases

The wait statistics script aggregates `WRITELOG` across all databases. To isolate the source, check I/O latency per file:

```sql
SELECT
    DB_NAME(vfs.database_id)    AS database_name,
    mf.name                     AS file_name,
    mf.type_desc,
    mf.physical_name,
    vfs.io_stall_write          AS write_stall_ms,
    vfs.num_of_writes,
    CASE WHEN vfs.num_of_writes > 0
         THEN vfs.io_stall_write / vfs.num_of_writes
         ELSE 0 END             AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id
    AND mf.file_id    = vfs.file_id
WHERE mf.type_desc = 'LOG'
ORDER BY vfs.io_stall_write DESC;
```

If the top rows are tempdb (`database_name = 'tempdb'`) and the production database log files show low latency, tempdb log pressure is the cause of your `WRITELOG` wait.

If production database log files show high latency, that's the `WRITELOG` post — this isn't a tempdb problem.

## What generates tempdb log writes

tempdb has a transaction log just like any other database. Unlike user databases, tempdb's log is not backed up and gets cleared on restart — but it still records operations in the log for rollback purposes during the session.

**Temporary table operations** — creating, inserting into, updating, and dropping `#temp` tables all generate log writes in tempdb. Row inserts into temp tables are fully logged (unlike bulk logged operations).

**Sort spills** — when a query's sort or hash operation can't fit in memory, it spills to tempdb worktables. Writing and reading those worktable rows generates tempdb I/O. The writes are logged in tempdb's log, contributing to `WRITELOG`.

**Row version store (RCSI and Snapshot Isolation)** — if Read Committed Snapshot Isolation (RCSI) is enabled on any database, SQL Server maintains row versions in tempdb's version store. Every modified row generates a version entry written to tempdb. Heavy update/delete workloads on RCSI-enabled databases can generate significant tempdb log writes.

**Table-Valued Parameters (TVPs)** — TVPs are materialised in tempdb. Passing large TVPs generates tempdb writes.

**Service Broker** — internal message tables for Service Broker live in tempdb by default. Active Service Broker workloads generate tempdb log writes.

**Online index operations** — `ALTER INDEX REBUILD WITH (ONLINE = ON)` uses a version store in tempdb for the duration of the rebuild.

## Diagnosing tempdb log pressure

**Confirm tempdb log latency (from the query above).**

**Find the top tempdb consumers right now:**

```sql
SELECT TOP 20
    s.session_id,
    s.login_name,
    s.program_name,
    s.host_name,
    su.user_objects_alloc_page_count                                                    AS user_obj_pages,
    su.internal_objects_alloc_page_count                                                AS internal_obj_pages,
    (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) * 8 / 1024 AS total_tempdb_mb
FROM sys.dm_db_session_space_usage su
JOIN sys.dm_exec_sessions s ON s.session_id = su.session_id
WHERE su.database_id = 2
  AND (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) > 128
ORDER BY total_tempdb_mb DESC;
```

`internal_objects_alloc_page_count` includes sort worktables (spills) — sessions with high internal page counts are spilling to disk.

**Identify spilling queries:**

```sql
SELECT TOP 20
    qs.total_spills / qs.execution_count  AS avg_spills,
    qs.total_spills,
    qs.execution_count,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS stmt_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.total_spills > 0
ORDER BY qs.total_spills DESC;
```

**Check version store size (if RCSI is in use):**

```sql
SELECT
    SUM(version_store_reserved_page_count) * 8 / 1024  AS version_store_mb
FROM sys.dm_db_file_space_usage
WHERE database_id = 2;
```

A version store above a few hundred MB is a sign that RCSI write pressure is contributing to tempdb log activity.

## What to do

**Move tempdb log file to fast dedicated storage** — this is the most direct fix. Tempdb's log file should be on SSDs or NVMe, ideally on its own dedicated volume separate from tempdb data files, production data, and production logs. This gives each of the four types of I/O a dedicated path.

**Fix sort spills** — spilling queries are the leading driver of tempdb load on most servers:

- Add missing indexes to eliminate unnecessary sorts:
  ```powershell
  .\run.ps1 Get-MissingIndexes
  ```
- Update statistics on tables involved in spilling queries
- Review memory grant configuration — is `RESOURCE_SEMAPHORE` also elevated? If so, workspace memory is too constrained overall.

**Reduce temp table write load**:
- Replace row-by-row inserts into temp tables with set-based inserts (one `INSERT INTO #temp SELECT ...` is far less log-intensive than a loop)
- Table variables (`@table`) are sometimes less logged than temp tables for small sets — but the tradeoffs are significant; don't use them blindly

**Manage RCSI version store growth**:
- Long-running read transactions on RCSI databases hold versions open for their entire duration. Identify and shorten long-running read transactions that are keeping version chains alive
- Check `sys.dm_tran_active_snapshot_database_transactions` for active snapshot transactions and their elapsed time

**Multiple tempdb data files** — adding data files (one per physical core, up to 8) reduces allocation contention on data pages, though it doesn't directly address log writes. Still worth having alongside the above fixes.

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script; see also the [WRITELOG post](writelog.md) for production log diagnosis
- [`Get-TempdbHotspots`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/health-checks/Get-TempdbHotspots.ps1) — allocation page contention in tempdb
- [`Get-MissingIndexes`](../missing-indexes/index.md) — fix the root cause of most spills
- [`Get-StatisticsHealth`](../statistics-health/index.md) — stale stats cause under-estimated memory grants leading to spills

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server tempdb WRITELOG

**Meta description** (151 chars — target 150–160):  
WRITELOG against tempdb is a separate bottleneck from production log writes. Heavy temp table use, sort spills, and row versioning all drive this wait.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `writelog-tempdb-io-stats.png` | sys.dm_io_virtual_file_stats filtered to tempdb showing high avg_write_ms on tempdb log file | tempdb log write latency |
| `writelog-tempdb-space-usage.png` | sys.dm_db_session_space_usage query showing sessions with high internal_objects_alloc_page_count (sort spills) | tempdb session usage by spills |
