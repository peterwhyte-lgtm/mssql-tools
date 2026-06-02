---
title: "SOS_SCHEDULER_YIELD Wait Type — SQL Server"
slug: sql-server-wait-statistics-sos-scheduler-yield
series: wait-statistics
series_position: 8
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, cpu, sos-scheduler-yield, scheduler]
seo_keyphrase: SQL Server SOS_SCHEDULER_YIELD
seo_title: "SQL Server SOS_SCHEDULER_YIELD — CPU Pressure Signal"
seo_description: SOS_SCHEDULER_YIELD means SQL Server threads are competing for CPU time. High values point to CPU saturation or runaway queries consuming all available cores. (155 chars)
screenshots_needed:
  - Get-WaitStatistics output showing SOS_SCHEDULER_YIELD prominently, with signal_wait_time_ms also elevated
  - sys.dm_os_schedulers output showing runnable_tasks_count > 1 on multiple schedulers
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# SOS_SCHEDULER_YIELD — CPU Scheduler Pressure

**Part of the [SQL Server Wait Statistics series](index.md)**

SQL Server uses a cooperative scheduling model. Rather than relying on the OS to preempt threads, SQL Server threads voluntarily yield the CPU at natural checkpoints after roughly 4ms of execution. When a thread yields, it moves to the runnable queue and waits for the scheduler to give it CPU time again. `SOS_SCHEDULER_YIELD` records that wait.

Some of this is normal and expected — it's how the cooperative scheduler works. High values, especially alongside elevated `signal_wait_time_ms` in the overall wait stats output, indicate the CPU schedulers are overloaded and threads are waiting longer than usual for their turn.

## Is this wait expected?

Some `SOS_SCHEDULER_YIELD` is always present. It's part of the scheduler's normal operation. It becomes a signal when:

- It's your #1 or #2 wait type by `pct_total_wait`
- `signal_wait_time_ms` in your overall wait stats is a large fraction of total wait time (signal wait = time waiting for CPU *after* a resource became available)
- CPU utilisation on the server is consistently above 80–90%
- Users report general sluggishness that doesn't correlate with a specific query or lock

## When to ignore it

**Normal background cooperative yielding** — a small amount of `SOS_SCHEDULER_YIELD` is inherent in how SQL Server schedules work. If it's in the top 10 but well below 10% of total wait time, it's probably just background noise.

**During batch operations** — large index rebuilds, DBCC CHECKDB, bulk loads, and columnstore compression all generate CPU work and consequently `SOS_SCHEDULER_YIELD`. Elevated values during known maintenance windows are expected.

**On lightly loaded servers** — the scheduler yields on every thread quantum, so even an idle server accumulates some of this wait. Look at `pct_total_wait` — if total wait time is low and SOS_SCHEDULER_YIELD is large only because other waits are also small, it's not a problem.

## Root causes

**CPU saturation** — more runnable threads than CPU cores can service. Every thread yield results in a longer queue wait because all schedulers are busy. This is the aggregate CPU pressure signal — it doesn't tell you *which* queries are responsible, only that the CPUs are overloaded.

**Runaway CPU query** — a single query executing a tight, non-yielding loop of CPU work. This can monopolise one or more schedulers and starve other threads. A query doing a massive hash join or an unindexed nested loop over millions of rows can be the sole cause.

**High MAXDOP with many concurrent queries** — parallel queries spawn many threads per query. If multiple large parallel queries run simultaneously, you can exhaust all schedulers even on a server with many cores.

**Excessive connections executing work simultaneously** — each active connection consuming CPU time competes for scheduler slots. This can happen during batch job spikes or when connection pooling is misconfigured and too many sessions are active.

**Non-yielding scheduler (rare)** — a thread that stops yielding at all (infinite loop, external code blocking, CLR issue) will eventually be detected as a non-yielding scheduler, generating an error log entry. This is rare but serious when it happens.

## How to diagnose it

**Check scheduler runnable queue depth:**

```sql
SELECT
    scheduler_id,
    cpu_id,
    status,
    runnable_tasks_count,
    current_tasks_count,
    work_queue_count,
    pending_disk_io_count
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE'
ORDER BY runnable_tasks_count DESC;
```

`runnable_tasks_count > 1` on multiple schedulers means threads are piling up waiting for CPU. If every scheduler shows `runnable_tasks_count >= 2`, you have genuine CPU saturation.

**Find current CPU-intensive queries:**

```sql
SELECT TOP 20
    r.session_id,
    r.cpu_time,
    r.total_elapsed_time,
    r.logical_reads,
    r.scheduler_id,
    r.wait_type,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1) AS current_statement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.status IN ('running', 'runnable')
ORDER BY r.cpu_time DESC;
```

**Find historically CPU-expensive queries:**

```sql
SELECT TOP 20
    qs.total_worker_time / qs.execution_count   AS avg_cpu_us,
    qs.total_worker_time,
    qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_worker_time DESC;
```

Queries with very high `avg_cpu_us` and high `avg_logical_reads` are the usual culprits — large scans doing CPU-intensive processing on the rows they touch.

**Check signal_wait_time in context:**

In the wait statistics script output, look at the `signal_wait_time_ms` column for all wait types. If signal wait is a large fraction of total wait time across the board (not just `SOS_SCHEDULER_YIELD`), the CPU schedulers are genuinely overloaded.

## What to do

**Find and tune the top CPU queries** — this is almost always the right starting point:

- Pull the top 10 queries by `total_worker_time` from `sys.dm_exec_query_stats`
- Look at their execution plans — are they doing table scans they shouldn't be?
- Add missing indexes to convert scans to seeks (fewer rows read = less CPU work)
- Review non-sargable predicates: `WHERE YEAR(date_column) = 2024` can't use an index; `WHERE date_column >= '2024-01-01' AND date_column < '2025-01-01'` can

**Reduce MAXDOP** — high parallelism amplifies CPU load. If many queries are running parallel and the server is CPU-saturated, reduce `max degree of parallelism` and raise the cost threshold for parallelism to limit when queries go parallel.

**Review concurrent workload** — are multiple batch jobs scheduled to run simultaneously? Stagger them to spread CPU load across time.

**Hardware** — if the workload is genuinely maxing out the CPUs and can't be tuned further, more cores or faster cores are the answer. SQL Server NUMA awareness means adding cores properly (not mismatched NUMA configurations) matters.

**Check for NUMA imbalance** — `sys.dm_os_schedulers` should show roughly equal runnable task counts across schedulers. If one CPU socket's schedulers are consistently more loaded, check NUMA configuration.

## Important: distinguish from CPU pressure vs. non-yielding

High `SOS_SCHEDULER_YIELD` from general CPU saturation is a very different problem from a single non-yielding scheduler. Check the SQL Server error log and Windows Event Log for "non-yielding scheduler" entries. If those exist, you may have a runaway thread or CLR/external component issue that needs immediate investigation.

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script; check signal_wait_time_ms column
- [`Get-TopCpuQueries`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-TopCpuQueries.ps1) — ranked CPU usage from the plan cache
- [`Get-MissingIndexes`](../missing-indexes/index.md) — indexes reduce scan work and CPU load

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server SOS_SCHEDULER_YIELD

**Meta description** (155 chars — target 150–160):  
SOS_SCHEDULER_YIELD means SQL Server threads are competing for CPU time. High values point to CPU saturation or runaway queries consuming all available cores.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `sos-scheduler-yield-wait-stats.png` | SQL Server wait statistics with SOS_SCHEDULER_YIELD at top and elevated signal_wait_time_ms column | SOS_SCHEDULER_YIELD in wait stats |
| `sos-scheduler-yield-schedulers.png` | sys.dm_os_schedulers output showing runnable_tasks_count of 3 and 4 on multiple CPU schedulers | Runnable task queue depth |
