---
title: "Script: Finding the Top CPU and I/O Queries in SQL Server"
slug: sql-server-top-cpu-io-queries
published: 
published_url: 
status: draft
category: performance
tags: [performance, cpu, io, plan-cache, queries, troubleshooting]
scripts:
  - sql/performance/Get-TopCpuQueries.sql
  - sql/performance/Get-TopIoQueries.sql
  - sql/performance/Get-SlowQueriesFromCache.sql
  - powershell/reporting/Get-TopCpuQueries.ps1
  - powershell/reporting/Get-TopIoQueries.ps1
seo_keyphrase: SQL Server top CPU queries
seo_title: "SQL Server Top CPU and I/O Queries from the Plan Cache"
seo_description: Find the queries consuming the most CPU and I/O in SQL Server using the plan cache. Includes avg and total metrics so you can distinguish frequent cheap vs. rare expensive queries. (183 chars — trim)
screenshots_needed:
  - Get-TopCpuQueries output showing database_name, execution_count, total_cpu_ms, avg_cpu_ms, and statement_text columns
  - Get-TopIoQueries equivalent output showing top I/O consuming queries
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Finding the Top CPU and I/O Queries in SQL Server

When a server is running hot — high CPU, slow queries, user complaints — you need to know quickly which queries are responsible. `sys.dm_exec_query_stats` tracks cumulative CPU time, I/O reads, elapsed time, and execution count for every query currently in the plan cache. Three focused scripts pull the top offenders by CPU, by I/O, and by elapsed time, ranked in a way that's immediately actionable.

## The problem

SQL Server doesn't have a built-in "what's making this server slow" view. You have to assemble it. The pieces are all in `sys.dm_exec_query_stats`, but the raw DMV has over 30 columns, returns thousands of rows, and doesn't tell you whether a query is expensive because it runs constantly or because it's occasionally enormous.

The scripts here surface the top 20 queries by CPU and I/O, with both total and average metrics so you can see both the high-frequency/cheap queries and the low-frequency/expensive ones. A query that runs a million times at 0.1ms average CPU has a huge total but isn't individually slow. A query that runs twice a day at 45 seconds average is a different kind of problem.

## The scripts

### Get-TopCpuQueries.sql

```sql
SELECT TOP (20)
    DB_NAME(st.dbid)                                                    AS database_name,
    qs.execution_count,
    qs.total_worker_time / 1000                                         AS total_cpu_ms,
    qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000        AS avg_cpu_ms,
    SUBSTRING(st.text,
        (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1
    )                                                                   AS statement_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_worker_time DESC;
```

### Get-TopIoQueries.sql

Same structure, ordered by `total_logical_reads` with `avg_logical_reads` included.

### Get-SlowQueriesFromCache.sql

Ordered by `total_elapsed_time / execution_count` — longest average elapsed time, which includes wait time (I/O waits, lock waits) that CPU-only metrics miss.

## How to run it from the repo

```powershell
# Top CPU queries
.\run.ps1 Get-TopCpuQueries

# Top I/O queries
.\run.ps1 Get-TopIoQueries

# Slowest queries by average elapsed time (includes waits)
.\run.ps1 Get-SlowQueriesFromCache

# Save all three for a performance baseline
.\run.ps1 Get-TopCpuQueries -OutputFormat Csv
.\run.ps1 Get-TopIoQueries -OutputFormat Csv
.\run.ps1 Get-SlowQueriesFromCache -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `database_name` | Which database the query runs against. `NULL` means it's not database-scoped (e.g. a server-level query or the database is no longer accessible). |
| `execution_count` | How many times this exact statement has run since SQL Server started (or the plan was last compiled). |
| `total_cpu_ms` | Cumulative CPU time across all executions. Ordered by this column to find the highest aggregate CPU consumers. |
| `avg_cpu_ms` | Average CPU per execution. A query with `total_cpu_ms = 60000` and `execution_count = 1,000,000` has `avg_cpu_ms = 0.06` — not individually slow, just frequent. The same total with `execution_count = 2` has `avg_cpu_ms = 30000` — occasionally catastrophic. |
| `statement_text` | The specific SQL statement — not the full batch, just the statement within the batch that corresponds to this stats row. For stored procedures, this shows the specific statement inside the proc. |

## Two ways a query appears in the top list

**High total, low average** — this query is cheap individually but runs constantly. It might be an index seek running 10 million times a day. The most effective fix is usually application-side (caching, reducing call frequency) rather than SQL-side.

**Low total, high average** — this query runs rarely but takes a very long time each time. It might be a reporting query doing a 20-million-row scan. The fix is usually SQL-side: missing index, missing filter, full-table scan that could be a seek.

Both patterns are worth investigating, but they have different fixes.

## Plan cache limitations

`sys.dm_exec_query_stats` only shows queries currently in the plan cache. A query plan can be evicted from cache by:

- SQL Server restart (clears all stats)
- Memory pressure evicting plans
- Explicit cache clear (`DBCC FREEPROCCACHE`)
- Plan recompilation

This means:
- You can't see queries that ran before the last restart
- You can't see rarely-used queries whose plans have been evicted
- You can't compare against historical baselines

**For historical data, use Query Store.** Query Store retains data across restarts and plan evictions, with configurable retention (default 30 days). See the [Query Store post](../query-store/index.md) for how to query it.

## What to do with a top query

Once you've identified a high-CPU or high-I/O query:

1. **Get the execution plan** — run the query in SSMS with "Include Actual Execution Plan" and look for:
   - Table scans on large tables (often fixable with an index)
   - Key lookups (suggest adding included columns to an existing index)
   - Hash joins on large data sets (sometimes fixable, sometimes expected)
   - Sort operators (may indicate missing index for ORDER BY or GROUP BY)

2. **Check for missing indexes** — the plan will show a "Missing Index" hint if the optimiser identified one:
   ```powershell
   .\run.ps1 Get-MissingIndexes
   ```

3. **Check parameter sniffing** — if the query performs fine on first run but poorly afterwards, or vice versa, a parameter sniffing issue may mean the cached plan is optimised for atypical parameter values. Look for large differences between estimated and actual rows in the plan.

4. **Check statistics** — bad cardinality estimates are the most common cause of poor plans:
   ```powershell
   .\run.ps1 Get-StatisticsHealth -Database YourDatabaseName
   ```

5. **Consider Query Store** for tracking this specific query's performance over time — especially after making changes.

## Related scripts

- [`Get-WaitStatistics`](../wait-statistics/index.md) — if wait stats show `SOS_SCHEDULER_YIELD`, this script will surface the CPU drivers
- [`Get-MissingIndexes`](../missing-indexes/index.md) — the usual fix for high-I/O queries
- [`Get-StatisticsHealth`](../statistics-health/index.md) — stale stats cause bad plans
- [`Get-QueryStoreTopQueries`](../query-store/index.md) — for historical CPU/IO trends that survive restarts

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-TopCpuQueries.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-TopCpuQueries.sql)
- [`sql/performance/Get-TopIoQueries.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-TopIoQueries.sql)
- [`sql/performance/Get-SlowQueriesFromCache.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-SlowQueriesFromCache.sql)

---

## SEO

**Focus keyphrase:** SQL Server top CPU queries

**Meta description** (trim to 160 before publishing — current: 183):  
Find the queries consuming the most CPU and I/O in SQL Server using the plan cache. Includes avg and total metrics so you can distinguish frequent cheap vs. rare expensive queries.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `top-cpu-queries-output.png` | Get-TopCpuQueries output showing top 20 queries ranked by total_cpu_ms with execution_count and avg_cpu_ms columns | Top CPU queries from plan cache |
| `top-io-queries-output.png` | Get-TopIoQueries output showing total_logical_reads and avg_logical_reads for top I/O consuming queries | Top I/O queries from plan cache |
