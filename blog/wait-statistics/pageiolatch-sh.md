---
title: "PAGEIOLATCH_SH Wait Type — SQL Server"
slug: sql-server-wait-statistics-pageiolatch-sh
series: wait-statistics
series_position: 2
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, io, pageiolatch, buffer-pool]
seo_keyphrase: SQL Server PAGEIOLATCH_SH
seo_title: "SQL Server PAGEIOLATCH_SH — Causes, False Positives, and Fixes"
seo_description: PAGEIOLATCH_SH means SQL Server is waiting to read a data page from disk. Learn when it's a real problem versus expected, and how to fix it. (148 chars)
screenshots_needed:
  - Get-WaitStatistics output in SSMS with PAGEIOLATCH_SH as the top wait type at 30%+ pct_total_wait
  - sys.dm_io_virtual_file_stats output showing high read_stall_ms on a data file
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# PAGEIOLATCH_SH — Data Page Read I/O Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

`PAGEIOLATCH_SH` appears when a query needs a data page that isn't in the buffer pool, so SQL Server must read it from disk. The SH stands for shared latch — the read operation. The query waits until the I/O completes and the page is loaded into memory.

This is one of the most common waits on servers where the working data set doesn't fit in RAM.

## Is this wait expected?

Some `PAGEIOLATCH_SH` is normal. Any server doing real work reads pages from disk occasionally. It becomes a signal worth investigating when:

- It's consistently in the top 3 wait types by `pct_total_wait`
- `pct_total_wait` is above 20% and trending upward
- `avg_wait_ms` is above 5ms on a consistent basis (not just during batch jobs)
- You're getting performance complaints and this is the top wait

## When to ignore it

**After a restart** — the buffer pool is empty. Everything is a cold read for the first hour or two. `PAGEIOLATCH_SH` will be high and then settle down. Normal.

**Nightly index rebuilds** — rebuilding an index evicts pages from cache and reads them back. Expect a spike during the maintenance window.

**Reporting and ETL queries** — a query doing a full table scan on a large table will always generate `PAGEIOLATCH_SH`. This may be expected for that workload. Compare: is `PAGEIOLATCH_SH` high only during batch windows, or all the time?

**Cold-cache first run** — a query that's just been compiled runs its pages for the first time. The second run won't wait at all. Not a problem.

## Root causes

**Buffer pool too small** — the most common cause. The server's working data set is larger than available RAM. SQL Server reads frequently-needed pages from disk because it can't keep them all in memory. The fix is more RAM, but see the diagnosis section first — sometimes it's a missing index making the buffer pool work too hard.

**Slow storage** — even if the buffer pool is sized correctly, a read that does reach disk on slow storage (spinning disk, overloaded SAN, shared iSCSI) will take longer. `avg_wait_ms` above 20ms regularly suggests a storage performance problem, not just a sizing one.

**Missing indexes causing large scans** — a query without the right index must scan thousands of pages instead of seeking to the right rows. This generates far more I/O than necessary and cycles through buffer pool pages faster than reads with good indexes.

**Large active working set** — even with plenty of RAM, a server running many distinct workloads may not be able to cache all of them effectively. Columnstore queries, ETL, OLTP, and reporting all compete for buffer pool space.

## How to diagnose it

First, confirm the wait is real and not a temporary spike:

Run the wait statistics script twice, 15–30 minutes apart, and compare the delta. If `PAGEIOLATCH_SH` is consistently in the top few positions in both snapshots, it's real.

**Find which databases and files are driving the reads:**

```sql
SELECT
    DB_NAME(vfs.database_id)        AS database_name,
    mf.physical_name,
    mf.type_desc,
    vfs.io_stall_read               AS read_stall_ms,
    vfs.num_of_reads,
    CASE WHEN vfs.num_of_reads > 0
         THEN vfs.io_stall_read / vfs.num_of_reads
         ELSE 0 END                 AS avg_read_ms,
    vfs.io_stall                    AS total_io_stall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id
    AND mf.file_id    = vfs.file_id
ORDER BY vfs.io_stall_read DESC;
```

Files with high `avg_read_ms` (above 15–20ms) indicate genuine storage latency. High read counts with low latency indicate buffer pool churn.

**Find which queries are doing the most reads:**

```sql
SELECT TOP 20
    qs.total_logical_reads / qs.execution_count  AS avg_logical_reads,
    qs.total_logical_reads,
    qs.execution_count,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_logical_reads DESC;
```

Queries with very high logical read counts are the ones evicting the buffer pool and generating page reads.

**Check missing indexes** — if logical reads are high on a table, check whether there's a missing index that would turn a scan into a seek:

```powershell
.\run.ps1 Get-MissingIndexes
```

## What to do

**If storage latency is high (`avg_read_ms` > 15ms consistently):**
- Move data files to faster storage (SSD or NVMe)
- Check if the storage array is shared and overloaded
- Check for disk queue depth in Windows Performance Monitor (`PhysicalDisk\Current Disk Queue Length`)

**If storage latency is fine but buffer pool churn is high:**
- Check available memory on the server — has SQL Server's max server memory been set too low?
- Look for other processes consuming RAM (antivirus scans, CLR, memory-leaking apps)
- Add RAM if the working set genuinely doesn't fit
- Add indexes to reduce logical read counts for the top-offending queries

**If it's a specific query causing the problem:**
- Add the missing index (validate with an execution plan first)
- Consider partitioning if only a subset of the table is needed
- Review whether the query needs to return all those rows, or whether it can be filtered earlier

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script that surfaces this wait type
- [`Get-MissingIndexes.ps1`](../missing-indexes/index.md) — find indexes that would reduce scan reads
- [`Get-DatabaseIoUsage.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-DatabaseIoUsage.ps1) — per-database I/O breakdown

## Get the scripts

The wait statistics script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server PAGEIOLATCH_SH

**Meta description** (148 chars — target 150–160):  
PAGEIOLATCH_SH means SQL Server is waiting to read a data page from disk. Learn when it's a real problem versus expected, and how to fix it.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `pageiolatch-sh-wait-stats.png` | SQL Server wait statistics output showing PAGEIOLATCH_SH as top wait type at 38% of total wait time | PAGEIOLATCH_SH as top wait type |
| `pageiolatch-sh-io-stats.png` | sys.dm_io_virtual_file_stats showing high read_stall_ms on a database data file | File I/O stall statistics |
