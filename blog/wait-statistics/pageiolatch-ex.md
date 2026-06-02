---
title: "PAGEIOLATCH_EX Wait Type — SQL Server"
slug: sql-server-wait-statistics-pageiolatch-ex
series: wait-statistics
series_position: 9
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, io, pageiolatch, writes, checkpoint]
seo_keyphrase: SQL Server PAGEIOLATCH_EX
seo_title: "SQL Server PAGEIOLATCH_EX — Data Page Write I/O Waits"
seo_description: PAGEIOLATCH_EX means SQL Server is waiting to write a dirty data page to disk. Learn the difference from PAGEIOLATCH_SH and what drives write I/O waits. (152 chars)
screenshots_needed:
  - Get-WaitStatistics output showing PAGEIOLATCH_EX — ideally alongside PAGEIOLATCH_SH for comparison
  - sys.dm_io_virtual_file_stats output showing high io_stall_write and avg_write_ms on a data file
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# PAGEIOLATCH_EX — Data Page Write I/O Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

`PAGEIOLATCH_EX` is the exclusive (write) variant of the page I/O latch wait. Where `PAGEIOLATCH_SH` means SQL Server is waiting to *read* a page from disk into the buffer pool, `PAGEIOLATCH_EX` means SQL Server is waiting to *write* a dirty page to disk.

Both point to storage as the bottleneck, but at different layers of the I/O path.

## PAGEIOLATCH_SH vs PAGEIOLATCH_EX — the distinction

| Wait type | Direction | Triggered by | Means |
|-----------|-----------|--------------|-------|
| `PAGEIOLATCH_SH` | Read | Query needing a page not in buffer pool | Cold reads — working set too large for RAM, or storage too slow |
| `PAGEIOLATCH_EX` | Write | Checkpoint, lazy writer flushing dirty pages | Write path — checkpoint frequency, heavy write workload, or slow storage writes |

In practice, `PAGEIOLATCH_SH` is far more common. `PAGEIOLATCH_EX` appearing at the top of your wait stats indicates the *write* path is the bottleneck — usually the checkpoint process or a heavy write workload generating dirty pages faster than the storage can flush them.

## Is this wait expected?

Some `PAGEIOLATCH_EX` is normal whenever SQL Server writes dirty pages to disk — which it does constantly via the checkpoint and lazy writer processes. It becomes significant when:

- It's in your top 3 wait types
- `avg_wait_ms` is high (above 10ms consistently)
- You're seeing performance degradation during write-heavy operations (large batch inserts, ETL loads, index rebuilds)
- It spikes alongside heavy write workloads and subsides when they finish

## Root causes

**Slow storage write path** — the checkpoint process can't write dirty pages fast enough. Spinning disk is much slower than SSD for random writes; NVMe is faster still. A server with fast reads (SSD) but slow writes (shared SAN write cache disabled) can show `PAGEIOLATCH_EX` without `PAGEIOLATCH_SH`.

**Checkpoint pressure from heavy write workloads** — large batch inserts, bulk loads, index rebuilds, or ETL processes generate many dirty pages rapidly. Checkpoint must flush these before the log can be reused, or before recovery time targets are met. More dirty pages = more write I/O = more `PAGEIOLATCH_EX`.

**Page splits from poor index design** — an index with a non-sequential key (GUIDs, random order) generates page splits on every insert. Each split writes a new page and updates existing pages, doubling write I/O versus a sequential insert. `PAGEIOLATCH_EX` can spike on tables with GUID-keyed clustered indexes under heavy insert load.

**Checkpoint not tuned for the workload** — the recovery interval server setting controls how often checkpoint fires. A very frequent checkpoint (low recovery interval) flushes pages aggressively and can cause `PAGEIOLATCH_EX` spikes. Too infrequent, and recovery time after a crash is long. The default (60 seconds with indirect checkpoint) is usually appropriate for 2016+.

**Instant file initialisation not enabled** — when SQL Server extends a data file (autogrowth event or initial allocation), it must zero-fill the new space unless Instant File Initialisation is enabled. Zeroing large file extensions causes `PAGEIOLATCH_EX` waits during the extension.

## How to diagnose it

**Check data file write latency:**

```sql
SELECT
    DB_NAME(vfs.database_id)        AS database_name,
    mf.physical_name,
    mf.type_desc,
    vfs.io_stall_write              AS write_stall_ms,
    vfs.num_of_writes,
    CASE WHEN vfs.num_of_writes > 0
         THEN vfs.io_stall_write / vfs.num_of_writes
         ELSE 0 END                 AS avg_write_ms,
    vfs.io_stall_read               AS read_stall_ms,
    vfs.num_of_reads,
    CASE WHEN vfs.num_of_reads > 0
         THEN vfs.io_stall_read / vfs.num_of_reads
         ELSE 0 END                 AS avg_read_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id
    AND mf.file_id    = vfs.file_id
WHERE mf.type_desc = 'ROWS'
ORDER BY vfs.io_stall_write DESC;
```

High `avg_write_ms` (above 10–15ms regularly) on data files confirms a storage write bottleneck.

**Check if checkpoint is the cause:**

```sql
-- Checkpoint stats since last restart
SELECT
    DB_NAME(database_id)            AS database_name,
    page_io_latch_wait_count,
    page_io_latch_wait_in_ms,
    checkpoint_pages_flushed
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.databases db ON db.database_id = vfs.database_id
-- correlate with checkpoint_latch_wait_count in sys.dm_db_log_stats
;
```

**Check for Instant File Initialisation:**

```sql
-- Look for autogrowth events coinciding with PAGEIOLATCH_EX spikes
-- Check sys.fn_trace_gettable for EventClass 92/93 (data/log autogrowth)
```

In Windows: check if the SQL Server service account has the "Perform volume maintenance tasks" local security right. If it does, IFI is enabled; if not, file extensions are zeroed.

**Check index page split frequency:**

```sql
SELECT
    OBJECT_NAME(i.object_id, DB_ID())  AS table_name,
    i.name                              AS index_name,
    i.fill_factor,
    ps.leaf_insert_count,
    ps.leaf_split_count,
    CAST(100.0 * ps.leaf_split_count /
        NULLIF(ps.leaf_insert_count + ps.leaf_split_count, 0) AS DECIMAL(5,1)) AS split_pct
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.leaf_split_count > 0
ORDER BY ps.leaf_split_count DESC;
```

A high split percentage on a table under heavy insert load indicates GUID or non-sequential key fragmentation.

## What to do

**Faster storage** — if `avg_write_ms` is high and the storage is spinning disk or an overloaded shared SAN, moving data files to SSD or NVMe is the most direct fix. Write latency on NVMe should be sub-millisecond.

**Enable Instant File Initialisation** — add the SQL Server service account to the "Perform volume maintenance tasks" local security policy. This eliminates the zeroing cost on file extensions. Requires a SQL Server service restart to take effect.

**Enable Indirect Checkpoint** — on SQL Server 2016+, indirect checkpoint is the default for new databases. For older databases or ones created before 2016, confirm it's set:

```sql
ALTER DATABASE [YourDatabase]
SET TARGET_RECOVERY_TIME = 60 SECONDS;  -- 60 seconds is the recommended default
```

Indirect checkpoint spreads write I/O more evenly over time rather than bursting. This reduces `PAGEIOLATCH_EX` spikes.

**Address page splits** — if the culprit is a GUID-keyed clustered index on a table with heavy inserts:
- Consider switching to a sequential key (IDENTITY, SEQUENCE, `newsequentialid()`)
- Or use a fill factor < 100 on the index to leave room for row insertions before splits are needed (trading space for fewer splits)

**Schedule write-heavy operations off-peak** — large bulk loads, index rebuilds, and batch updates that generate checkpoint pressure should run during maintenance windows to avoid competing with production I/O.

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script; shows PAGEIOLATCH_EX alongside SH
- [`Get-IndexFragmentation`](../index-fragmentation/index.md) — high fragmentation often accompanies page split issues
- [`Get-DatabaseIoUsage`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-DatabaseIoUsage.ps1) — per-database I/O breakdown

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server PAGEIOLATCH_EX

**Meta description** (152 chars — target 150–160):  
PAGEIOLATCH_EX means SQL Server is waiting to write a dirty data page to disk. Learn the difference from PAGEIOLATCH_SH and what drives write I/O waits.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `pageiolatch-ex-wait-stats.png` | SQL Server wait statistics showing PAGEIOLATCH_EX with high avg_wait_ms on data file writes | PAGEIOLATCH_EX write wait |
| `pageiolatch-ex-io-stats.png` | sys.dm_io_virtual_file_stats showing high io_stall_write and avg_write_ms on SQL Server data files | Data file write latency |
