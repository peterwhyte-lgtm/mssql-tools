---
title: "IO_COMPLETION Wait Type — SQL Server"
slug: sql-server-wait-statistics-io-completion
series: wait-statistics
series_position: 10
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, io, io-completion, tempdb, backup, spills]
seo_keyphrase: SQL Server IO_COMPLETION wait
seo_title: "SQL Server IO_COMPLETION — Non-Data I/O Waits Explained"
seo_description: SQL Server IO_COMPLETION covers I/O waits for sort spills to tempdb, backup operations, and DBCC. Learn how to identify which cause is driving it on your server. (159 chars)
screenshots_needed:
  - Get-WaitStatistics output showing IO_COMPLETION in top wait types
  - sys.dm_exec_query_stats query showing queries with high total_spills and avg_spills per execution
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# IO_COMPLETION — Non-Data File I/O Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

`IO_COMPLETION` covers I/O waits that happen *outside* the normal buffer pool page path. Where `PAGEIOLATCH_SH` and `PAGEIOLATCH_EX` track data page reads and writes through the buffer pool, `IO_COMPLETION` tracks everything else: sort spills to tempdb worktables, backup file writes, restore reads, and DBCC work file I/O.

The wait type name is generic, which makes it harder to diagnose than the `PAGEIOLATCH_*` family. The first step is always figuring out what type of I/O is generating the wait.

## What generates IO_COMPLETION

**Sort spills to tempdb** — the most common cause in production. When a query doesn't get enough memory to complete a sort or hash operation in-memory, it spills to disk — writing and reading back worktable rows in tempdb. Each spill read and write generates `IO_COMPLETION`. Unlike `PAGEIOLATCH_*`, these are worktable pages, not buffer pool pages, so they appear as `IO_COMPLETION` instead.

**Backup operations** — writing backup data to disk (or a network share) generates `IO_COMPLETION` on the backup I/O threads. If backup jobs are running, elevated `IO_COMPLETION` is expected.

**DBCC CHECKDB and DBCC CHECKTABLE** — DBCC creates internal work files in tempdb for its snapshot and processing work. Large databases running DBCC will show `IO_COMPLETION`.

**Database restore** — reading backup files during a restore generates `IO_COMPLETION` on the restore threads.

**Bulk operations using row set caches** — some bulk insert paths use tempdb staging that goes through `IO_COMPLETION` rather than the buffer pool.

## Is this wait expected?

**During backup windows** — yes. If your backup job runs at midnight and `IO_COMPLETION` spikes then, it's just the backup. Check the timing correlation.

**During DBCC runs** — yes. DBCC CHECKDB on a large database generates substantial tempdb I/O.

**Outside of maintenance windows** — investigate. `IO_COMPLETION` during production hours usually means sort spills, which means queries aren't getting the memory they need (missing indexes or stale stats) or tempdb I/O is slow.

## How to identify the cause

**Check whether backup jobs are running:**

```sql
SELECT
    job.name                        AS job_name,
    ja.start_execution_date,
    ja.last_executed_step_date,
    jh.run_status
FROM msdb.dbo.sysjobs job
JOIN msdb.dbo.sysjobactivity ja ON ja.job_id = job.job_id
JOIN msdb.dbo.sysjobhistory jh  ON jh.job_id = job.job_id
WHERE ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date  IS NULL
ORDER BY ja.start_execution_date DESC;
```

Or simply check if `BACKUPIO` is also elevated in the wait stats — backup operations generate both.

**Find queries that are spilling to tempdb:**

```sql
SELECT TOP 20
    qs.total_spills / qs.execution_count  AS avg_spills_per_exec,
    qs.total_spills,
    qs.execution_count,
    qs.total_grant_kb / qs.execution_count AS avg_grant_kb,
    qs.total_worker_time / qs.execution_count AS avg_cpu_us,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.total_spills > 0
ORDER BY qs.total_spills DESC;
```

Queries with `avg_spills_per_exec > 0` are consistently spilling. The higher the number, the worse the spill.

**Check tempdb I/O specifically:**

```sql
SELECT
    mf.name                         AS file_name,
    mf.type_desc,
    mf.physical_name,
    vfs.io_stall_write / 1000.0     AS write_stall_sec,
    vfs.io_stall_read  / 1000.0     AS read_stall_sec,
    vfs.num_of_writes,
    vfs.num_of_reads,
    CASE WHEN vfs.num_of_writes > 0
         THEN vfs.io_stall_write / vfs.num_of_writes ELSE 0 END AS avg_write_ms,
    CASE WHEN vfs.num_of_reads  > 0
         THEN vfs.io_stall_read  / vfs.num_of_reads  ELSE 0 END AS avg_read_ms
FROM sys.dm_io_virtual_file_stats(2, NULL) vfs   -- database_id 2 = tempdb
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id
    AND mf.file_id    = vfs.file_id
ORDER BY vfs.io_stall_write + vfs.io_stall_read DESC;
```

High `avg_write_ms` or `avg_read_ms` on tempdb data files during production hours, combined with spilling queries, confirms sort spills are the cause.

**Find who is using tempdb the most right now:**

```sql
SELECT TOP 20
    s.session_id,
    s.program_name,
    s.host_name,
    su.user_objects_alloc_page_count    AS user_obj_pages,
    su.internal_objects_alloc_page_count AS internal_obj_pages,
    su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count AS total_pages,
    (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) * 8 / 1024 AS total_mb
FROM sys.dm_db_session_space_usage su
JOIN sys.dm_exec_sessions s ON s.session_id = su.session_id
WHERE su.database_id = 2  -- tempdb
  AND (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) > 0
ORDER BY total_pages DESC;
```

`internal_objects_alloc_page_count` includes sort worktables (spills). Sessions with high internal object usage are the spilling queries.

## What to do

**For sort spills (the most common cause):**

The root cause is almost always a missing index or stale statistics. A query that spills to disk is doing work it shouldn't need to do.

1. Identify the spilling queries from `dm_exec_query_stats` above
2. Run their execution plans in SSMS with "Include Actual Execution Plan" — look for Sort operators with a yellow warning triangle ("Warnings: Operator used tempdb to spill data")
3. Check for missing indexes on the tables involved:

```powershell
.\run.ps1 Get-MissingIndexes
```

4. Update statistics on the involved tables
5. If the query legitimately needs to sort large data sets (e.g. a reporting query), consider whether the result set can be reduced before sorting

**For tempdb I/O performance in general:**
- Tempdb data files should be on fast storage — ideally the same SSD/NVMe tier as production data
- Multiple tempdb data files (one per physical core, up to 8) reduce allocation contention, though they don't directly improve sort spill I/O

**For backup-driven IO_COMPLETION:**
- Enable backup compression — less data written means faster backup I/O
- Schedule backups during low-traffic windows
- Consider offloading backups to an AG secondary replica

**For DBCC-driven IO_COMPLETION:**
- Run DBCC CHECKDB during off-peak hours
- On Enterprise Edition, DBCC with `PHYSICAL_ONLY` is faster and generates less tempdb I/O (though it checks less)

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script
- [`Get-MissingIndexes`](../missing-indexes/index.md) — the usual fix for sort spills
- [`Get-StatisticsHealth`](../statistics-health/index.md) — stale stats cause bad memory grant estimates leading to spills
- [`Get-TempdbHotspots`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/health-checks/Get-TempdbHotspots.ps1) — tempdb allocation contention

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server IO_COMPLETION wait

**Meta description** (159 chars — target 150–160):  
SQL Server IO_COMPLETION covers I/O waits for sort spills to tempdb, backup operations, and DBCC. Learn how to identify which cause is driving it on your server.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `io-completion-wait-stats.png` | SQL Server wait statistics showing IO_COMPLETION in top wait types during production hours | IO_COMPLETION in wait stats |
| `io-completion-spills.png` | sys.dm_exec_query_stats output showing queries with avg_spills_per_exec greater than zero | Queries spilling to tempdb |
