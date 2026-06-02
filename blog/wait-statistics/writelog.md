---
title: "WRITELOG Wait Type — SQL Server"
slug: sql-server-wait-statistics-writelog
series: wait-statistics
series_position: 3
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, transaction-log, writelog, io]
seo_keyphrase: SQL Server WRITELOG wait
seo_title: "SQL Server WRITELOG Wait — Log Disk Pressure and Chatty Commits"
seo_description: SQL Server WRITELOG waits mean transaction log writes are slow. Understand the causes — slow log disk, chatty commits, or AG lag — and how to fix each. (153 chars)
screenshots_needed:
  - Get-WaitStatistics output showing WRITELOG as the dominant wait type with high avg_wait_ms
  - sys.dm_io_virtual_file_stats query result showing high write_stall_ms on a log file
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# WRITELOG — Transaction Log Write Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

Every committed transaction in SQL Server must wait for its log records to be written to disk before the commit is acknowledged. `WRITELOG` is the wait for that write to complete. It's present on every transactional system — the question is whether it's high enough to be a real bottleneck.

SQL Server writes log records in batches (log blocks), flushing them when a commit occurs or the log buffer fills. `WRITELOG` measures the time from "flush requested" to "flush completed." Anything that slows the log disk, or increases flush frequency, raises this wait.

## Is this wait expected?

Yes — some `WRITELOG` is inherent in any transactional workload. The question is whether it's in proportion to the work being done.

Signs it's a real problem:
- `WRITELOG` is consistently the #1 or #2 wait type
- `avg_wait_ms` is above 3–5ms (on modern storage, log writes should be sub-millisecond)
- You're seeing slow insert/update performance and this is the dominant wait
- `max_wait_time_ms` is very high (occasional I/O stalls — the worst kind)

## When to ignore it

**High transaction volume workloads** — if you're doing tens of thousands of commits per second, some WRITELOG is unavoidable. Focus on `avg_wait_ms`, not just the total.

**Bulk load operations** — a large bulk insert with minimal logging will spike WRITELOG briefly then settle. One-off events aren't a problem.

**High Availability groups (synchronous commit)** — the log hardening wait in synchronous AG (`HADR_SYNC_COMMIT`) interacts with `WRITELOG`. If the secondary is slow, you'll see `WRITELOG` elevated on the primary. This is really a `HADR_SYNC_COMMIT` problem — check that wait type too.

## Root causes

**Slow log disk** — the most common cause. Log writes are sequential and frequent. The log file should be on the fastest storage available. Spinning disk, shared SANs, or log files sharing a volume with data files all degrade this. `avg_read_ms` on the log file in `sys.dm_io_virtual_file_stats` should be below 1–2ms on SSD.

**Log file shared with data files** — a very common configuration mistake, especially on test/dev servers promoted to production. Data reads are random; log writes are sequential. Mixing them on the same disk creates I/O contention.

**Chatty commit patterns** — applications that commit after every row insert, or that use a tight BEGIN TRAN / COMMIT loop, generate far more log flushes than necessary. Each commit is a separate log write request. Batching 1000 row inserts into one transaction reduces log write frequency by 1000x.

**Very high transaction rate** — some WRITELOG at high TPS is unavoidable. At very high rates, the log disk throughput can simply become a ceiling.

**AG synchronous secondary lag** — with synchronous commit AGs, the primary must wait for the secondary to harden the log before committing. A slow secondary network or slow secondary disk shows up as WRITELOG on the primary, combined with elevated `HADR_SYNC_COMMIT`.

## How to diagnose it

**Check log file I/O latency:**

```sql
SELECT
    DB_NAME(vfs.database_id)        AS database_name,
    mf.physical_name,
    vfs.io_stall_write              AS write_stall_ms,
    vfs.num_of_writes,
    CASE WHEN vfs.num_of_writes > 0
         THEN vfs.io_stall_write / vfs.num_of_writes
         ELSE 0 END                 AS avg_write_ms,
    vfs.io_stall                    AS total_io_stall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id
    AND mf.file_id    = vfs.file_id
WHERE mf.type_desc = 'LOG'
ORDER BY vfs.io_stall_write DESC;
```

`avg_write_ms` above 2–5ms consistently indicates the log disk is the bottleneck. Above 20ms means the disk is genuinely undersized or overloaded.

**Check if sessions are currently in WRITELOG wait:**

```sql
SELECT
    r.session_id,
    r.wait_type,
    r.wait_time / 1000.0            AS wait_sec,
    r.blocking_session_id,
    DB_NAME(r.database_id)          AS database_name,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1) AS current_statement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.wait_type = 'WRITELOG'
ORDER BY r.wait_time DESC;
```

**Check if it's an AG issue:**

```sql
SELECT
    replica_id,
    log_send_queue_size,
    log_send_rate,
    redo_queue_size,
    synchronization_state_desc
FROM sys.dm_hadr_database_replica_states
WHERE is_local = 0;
```

A high `log_send_queue_size` indicates the secondary can't keep up.

## What to do

**Slow log disk:**
- Move the log file to a dedicated fast disk (SSD or NVMe ideally)
- Separate log files from data files if they share a volume
- Check storage queue depth in Performance Monitor (`PhysicalDisk\Current Disk Queue Length` on the log volume)

**Chatty commit patterns:**
- Identify the application or job doing frequent small commits
- Refactor row-by-row inserts into set-based operations
- Or batch commits — instead of committing after every row, commit every 500 or 1000 rows
- Review SSIS or ETL packages for `Row by Row` commit modes

**AG secondary lag:**
- Check network latency between primary and secondary
- Check secondary disk write performance
- For geographically distant secondaries, evaluate whether asynchronous commit is more appropriate

**As a temporary measure only:**
- For write-heavy applications under strict SLA, delayed durability (`DELAYED_DURABILITY = FORCED`) can reduce `WRITELOG` by batching log flushes. This trades write performance for a small data loss window — appropriate only for specific use cases (audit logs, telemetry) not for transactional data.

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script
- [`Get-VlfCount`](../vlf-count/index.md) — VLF count affects log flush behavior; high VLF counts can compound WRITELOG waits
- [`Get-TransactionLogSizeAndUsage`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/inventory/Get-TransactionLogSizeAndUsage.ps1) — log file sizing and usage

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server WRITELOG wait

**Meta description** (153 chars — target 150–160):  
SQL Server WRITELOG waits mean transaction log writes are slow. Understand the causes — slow log disk, chatty commits, or AG lag — and how to fix each.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `writelog-wait-stats.png` | SQL Server wait statistics showing WRITELOG as top wait type with avg_wait_ms over 10ms | WRITELOG as dominant wait type |
| `writelog-io-stats.png` | sys.dm_io_virtual_file_stats showing high write_stall_ms on transaction log file | Log file write latency |
