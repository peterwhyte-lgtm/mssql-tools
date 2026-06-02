---
title: "RESOURCE_SEMAPHORE Wait Type — SQL Server"
slug: sql-server-wait-statistics-resource-semaphore
series: wait-statistics
series_position: 7
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, memory, resource-semaphore, memory-grants]
seo_keyphrase: SQL Server RESOURCE_SEMAPHORE
seo_title: "SQL Server RESOURCE_SEMAPHORE — Memory Grant Queue Waits"
seo_description: RESOURCE_SEMAPHORE means queries are queuing for memory grants before they can run. Almost always caused by missing indexes or stale statistics. (144 chars)
screenshots_needed:
  - Get-WaitStatistics output showing RESOURCE_SEMAPHORE in top wait types
  - sys.dm_exec_query_memory_grants output showing pending grants with requested_memory_kb and wait_time_ms
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# RESOURCE_SEMAPHORE — Memory Grant Queue Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

Before SQL Server runs a query that sorts or hashes large data sets, it requests a memory reservation — called a memory grant — from the resource semaphore. The semaphore controls how much of the total server memory can be allocated for query workspace at once. If the request can't be granted immediately (not enough free workspace memory), the query waits here.

`RESOURCE_SEMAPHORE` is one of the more consequential wait types. It doesn't mean a query is running slowly — it means queries can't start running at all. They're parked in a queue waiting for other queries to finish and release their grants.

## Is this wait expected?

No, not meaningfully. Some very brief waits during memory pressure spikes are possible, but `RESOURCE_SEMAPHORE` appearing consistently in your top waits is always a signal worth investigating.

Unlike `CXPACKET` or `ASYNC_NETWORK_IO` which are often acceptable, `RESOURCE_SEMAPHORE` almost always points to something actionable — usually a missing index causing unnecessarily large sort or hash operations, or inaccurate statistics causing SQL Server to misestimate how much memory a query needs.

## Root causes

**Missing indexes causing large sort or hash operations** — the most common cause. A query that lacks a covering index can't seek to just the rows it needs. Instead it scans a large table, then sorts or hashes the results. That sort needs a big memory grant. With the right index, the query runs as a seek, needs no sort, and needs no memory grant at all.

**Stale or inaccurate statistics causing over-estimation** — if statistics are out of date, SQL Server might overestimate how many rows a query will process, request a larger memory grant than necessary, and hold a disproportionate share of workspace memory while running.

**Stale statistics causing under-estimation and spills** — the opposite problem. If SQL Server underestimates rows, it requests too small a grant. The query starts but runs out of workspace memory and spills to tempdb. Spilling queries often re-request larger grants on the next run, creating contention. Check `IO_COMPLETION` and `total_spills` alongside `RESOURCE_SEMAPHORE`.

**Too many concurrent memory-intensive queries** — even if individual queries are efficient, if many run simultaneously and each requests a large grant, the pool is exhausted. More a scheduling problem than a query problem.

**Max server memory set too low** — workspace memory is a percentage of max server memory. If max server memory is constrained (left at default or misconfigured), the workspace pool is smaller than it should be.

## How to diagnose it

**See what's currently waiting and what's been granted:**

```sql
SELECT
    session_id,
    request_time,
    grant_time,
    requested_memory_kb,
    granted_memory_kb,
    used_memory_kb,
    max_used_memory_kb,
    queue_id,
    wait_order,
    is_next_candidate,
    wait_time_ms,
    plan_handle
FROM sys.dm_exec_query_memory_grants
ORDER BY
    CASE WHEN queue_id IS NOT NULL THEN 0 ELSE 1 END,  -- pending first
    wait_time_ms DESC;
```

Sessions with a non-null `queue_id` are waiting. `wait_order` shows their position in the queue. `requested_memory_kb` shows how much they need to start.

**Find queries that historically consume large memory grants:**

```sql
SELECT TOP 20
    qs.total_grant_kb / qs.execution_count           AS avg_grant_kb,
    qs.max_grant_kb,
    qs.total_spills / qs.execution_count             AS avg_spills,
    qs.execution_count,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.total_grant_kb > 0
ORDER BY qs.total_grant_kb DESC;
```

High `avg_grant_kb` with `avg_spills > 0` means SQL Server's estimates are consistently wrong — under-grants leading to spills.

**Check workspace memory configuration:**

```sql
SELECT
    physical_memory_in_use_kb / 1024    AS sql_memory_used_mb,
    page_fault_count,
    memory_utilization_percentage
FROM sys.dm_os_process_memory;

SELECT value_in_use
FROM sys.configurations
WHERE name = 'max server memory (MB)';
```

If `memory_utilization_percentage` is consistently near 100 and `RESOURCE_SEMAPHORE` is high, max server memory may be too constrained.

**Check for missing indexes on tables in the problematic queries** — pull the query text from `dm_exec_query_memory_grants`, identify the tables, and run:

```powershell
.\run.ps1 Get-MissingIndexes
```

## What to do

**Add missing indexes** — this is the fix most of the time. A query that was scanning 5 million rows to sort the result becomes a seek returning 200 rows with no sort at all. The memory grant drops from hundreds of megabytes to nothing.

**Update statistics** — bad cardinality estimates produce both over-grants (hogging workspace memory) and under-grants (causing spills). Update statistics on the tables involved in the offending queries:

```sql
UPDATE STATISTICS [schema].[table_name] WITH FULLSCAN;
```

For persistent under-estimation on a rapidly changing table, consider increasing the automatic update statistics threshold (SQL Server 2016+ with compat level 130 has a dynamic threshold — enable it if not already on).

**Review max server memory** — if workspace memory is genuinely too small, increasing max server memory gives the workspace pool more room:

```sql
EXEC sp_configure 'max server memory (MB)', 32768;  -- example: 32 GB
RECONFIGURE;
```

Leave headroom for the OS and other processes — generally don't allocate more than 80–90% of physical RAM to SQL Server.

**Use Resource Governor (Enterprise)** — to cap memory grants per workload group, preventing one class of queries from starving others:

```sql
ALTER RESOURCE POOL [reporting_pool] WITH (MAX_MEMORY_PERCENT = 30);
```

**Query hints for specific known-bad queries:**

```sql
-- Cap a specific query's grant to prevent it monopolising workspace memory
SELECT ... FROM ... WHERE ...
OPTION (MAX_GRANT_PERCENT = 10);

-- Force a minimum grant for a query that keeps getting under-granted and spilling
OPTION (MIN_GRANT_PERCENT = 5);
```

Use hints only as a temporary measure while you fix the underlying index or statistics problem.

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script
- [`Get-MissingIndexes`](../missing-indexes/index.md) — the first place to look after finding this wait
- [`Get-StatisticsHealth`](../statistics-health/index.md) — find stale statistics contributing to bad estimates

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server RESOURCE_SEMAPHORE

**Meta description** (144 chars — target 150–160 — extend before publishing):  
RESOURCE_SEMAPHORE means queries are queuing for memory grants before they can run. Almost always caused by missing indexes or stale statistics.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `resource-semaphore-wait-stats.png` | SQL Server wait statistics showing RESOURCE_SEMAPHORE in top waits with high avg_wait_ms | RESOURCE_SEMAPHORE in wait stats |
| `resource-semaphore-grants.png` | sys.dm_exec_query_memory_grants showing pending memory grant requests with wait_time_ms | Pending memory grant queue |
