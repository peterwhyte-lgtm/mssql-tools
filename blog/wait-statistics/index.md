---
title: SQL Server Wait Statistics Explained
slug: sql-server-wait-statistics
published: 
status: draft
category: performance
tags: [performance, waits, triage, dmv]
scripts:
  - sql/performance/Get-WaitStatistics.sql
  - powershell/reporting/Get-WaitStatistics.ps1
seo_keyphrase:    SQL Server wait statistics
seo_title:        SQL Server Wait Statistics Explained
seo_description:  Learn how to diagnose SQL Server performance problems using wait statistics. This script filters background noise and ranks the waits that actually matter. (155 chars)
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# SQL Server Wait Statistics Explained

Wait statistics are the single best first step in any SQL Server performance investigation. Every time a query has to wait for something — a lock, a disk read, a log write, a memory grant — SQL Server records it. By the time you have a performance complaint, the answer is usually already sitting in `sys.dm_os_wait_stats`, waiting to be read.

The challenge is that SQL Server tracks dozens of wait types, and most of them are noise — background processes sleeping, idle schedulers checking in, internal broker activity. This post walks through how to filter that out and focus on the waits that actually tell you something.

## The problem

Without wait statistics, a slow server is a black box. Is it the disk? Locking? CPU queue? Parallelism overhead? Memory pressure? Each of those requires a completely different fix, and the wrong diagnosis wastes hours.

Wait stats give you a ranked list of where time is being lost. If `PAGEIOLATCH_SH` is 60% of your total wait time, your I/O subsystem is the bottleneck. If `WRITELOG` dominates, your transaction log disk is the problem. If `RESOURCE_SEMAPHORE` appears, queries are queuing for memory grants. The stat points you at the right layer to investigate next.

The catch: SQL Server also records a lot of completely harmless waits — `SLEEP_TASK`, `LAZYWRITER_SLEEP`, `BROKER_TO_FLUSH` and others that represent SQL Server's own background processes doing nothing. If you don't filter these out, they dominate the output and hide the real signals.

## The script

```sql
WITH filtered_waits AS (
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0
      AND wait_type NOT IN (
          'SLEEP_TASK',                     'SLEEP_SYSTEMTASK',
          'SLEEP_TEMPDBSTARTUP',            'SLEEP_DBSTARTUP',
          'SLEEP_DCOMSTARTUP',              'SLEEP_MASTERDBREADY',
          'SLEEP_MASTERMDREADY',            'SLEEP_MASTERUPGRADED',
          'SLEEP_MSDBSTARTUP',              'SNI_HTTP_ACCEPT',
          'DISPATCHER_QUEUE_SEMAPHORE',     'BROKER_TO_FLUSH',
          'BROKER_TASK_STOP',               'BROKER_EVENTHANDLER',
          'BROKER_RECEIVE_WAITFOR',         'CHECKPOINT_QUEUE',
          'DBMIRROR_EVENTS_QUEUE',          'DBMIRROR_WORKER_QUEUE',
          'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_BUFFER_FLUSH',
          'SQLTRACE_WAIT_ENTRIES',          'WAITFOR',
          'LAZYWRITER_SLEEP',               'LOGMGR_QUEUE',
          'ONDEMAND_TASK_QUEUE',            'REQUEST_FOR_DEADLOCK_SEARCH',
          'RESOURCE_QUEUE',                 'SERVER_IDLE_CHECK',
          'SP_SERVER_DIAGNOSTICS_SLEEP',    'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
          'XE_DISPATCHER_WAIT',             'XE_TIMER_EVENT',
          'HADR_WORK_QUEUE',                'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
          'HADR_CLUSAPI_CALL',              'HADR_NOTIFICATION_DEQUEUE',
          'FT_IFTS_SCHEDULER_IDLE_WAIT',    'FT_IFTSHC_MUTEX',
          'REPL_WORK_QUEUE',                'CLR_AUTO_EVENT',
          'CLR_MANUAL_EVENT',               'WAIT_XTP_COMPILE_WAIT'
      )
)
SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(5,2)) AS pct_total_wait,
    CAST(wait_time_ms / NULLIF(waiting_tasks_count, 0) AS DECIMAL(10,0))              AS avg_wait_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    resource_wait_time_ms
FROM filtered_waits
ORDER BY wait_time_ms DESC;
```

## How to run it from the repo

```powershell
# Table output — quick triage view
.\run.ps1 Get-WaitStatistics

# Save to CSV for comparison over time
.\run.ps1 Get-WaitStatistics -OutputFormat Csv

# Against a named instance
.\run.ps1 Get-WaitStatistics -ServerInstance MYSERVER\INST01 -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `wait_type` | Name of the wait. The SQL Server documentation has a full list. |
| `waiting_tasks_count` | How many tasks have waited on this type since the last restart |
| `wait_time_ms` | Total cumulative wait time in milliseconds since last restart |
| `pct_total_wait` | This wait type's share of all non-idle wait time. The most useful column for ranking. |
| `avg_wait_ms` | Average wait time per occurrence — helps distinguish frequent short waits from rare long ones |
| `max_wait_time_ms` | Longest single wait ever recorded for this type |
| `signal_wait_time_ms` | Time spent waiting for a CPU scheduler slot *after* the resource became available. High values here indicate CPU pressure. |
| `resource_wait_time_ms` | Time waiting for the actual resource (I/O, lock, memory, etc.) |

The `pct_total_wait` column is the one to sort by mentally. The top two or three wait types that together account for 60–80% of total wait time are your investigation targets.

## What to look for

**`PAGEIOLATCH_SH` / `PAGEIOLATCH_EX`** — Data page I/O. The query needed a page from disk and had to wait for it to load. Usually means either the buffer pool is too small (data doesn't fit in RAM), or the storage subsystem is slow.

**`WRITELOG`** — Transaction log write waits. Every committed transaction must wait for its log records to be written. Dominates when the log disk is slow or when you have high-frequency small transactions.

**`RESOURCE_SEMAPHORE`** — Memory grant waits. Queries that sort or hash large datasets need a memory reservation. If available memory is low, queries queue here. Often associated with missing indexes causing large sort/hash operations.

**`CXPACKET` / `CXCONSUMER`** — Parallelism coordination. Some degree is normal. Very high values suggest MAXDOP is set too high, or cost threshold for parallelism is too low, causing even trivial queries to go parallel.

**`LCK_M_X` / `LCK_M_S`** — Lock waits. Exclusive and shared locks. High values mean blocking is happening regularly. Investigate with the blocking scripts.

**`ASYNC_NETWORK_IO`** — Client network waits. SQL Server produced results but the application wasn't reading them fast enough. Usually an application-layer issue, not a SQL Server one.

**`signal_wait_time_ms` is large relative to `resource_wait_time_ms`** — This means queries got their resource but then waited for CPU. Points to CPU saturation.

Normal healthy instances tend to show `CXPACKET` in a small amount, maybe some `PAGEIOLATCH` if the server is doing real work, and nothing else above 10%. If a single wait type is 40%+ of total, that's a clear bottleneck signal.

## Important: these are cumulative since last restart

`sys.dm_os_wait_stats` accumulates from the moment SQL Server started. On a server that's been up for 6 months, today's problem might be buried under months of historical data. If you're investigating a specific incident, compare two snapshots taken before and after the problem window, or use a baseline snapshot tool.

## Related scripts in this repo

- [`Get-LongRunningQueries.sql`](../sql/performance/Get-LongRunningQueries.sql) — see which active queries are currently waiting and what type
- [`Get-BlockingSessions.sql`](../sql/performance/Get-BlockingSessions.sql) — if `LCK_M_*` waits are high, start here
- [`Get-DatabaseIoUsage.sql`](../sql/performance/Get-DatabaseIoUsage.sql) — if `PAGEIOLATCH` is high, see which databases are driving I/O

## Get the scripts

The full script is available in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server wait statistics

**Meta description** (155 chars — target 150–160):  
Learn how to diagnose SQL Server performance problems using wait statistics. This script filters background noise and ranks the waits that actually matter.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `wait-stats-output.png` | SQL Server wait statistics query output showing top wait types ranked by pct_total_wait with PAGEIOLATCH_SH at 38% | SQL Server wait statistics DMV output |
