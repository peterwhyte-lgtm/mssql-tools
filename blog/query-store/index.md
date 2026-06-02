---
title: "Script: Finding Top Queries and Regressions with SQL Server Query Store"
slug: sql-server-query-store-top-queries
published: 
published_url: 
status: draft
category: performance
tags: [query-store, performance, regressions, query-tuning]
scripts:
  - sql/performance/Get-QueryStoreTopQueries.sql
seo_keyphrase: SQL Server Query Store top queries
seo_title: "Using SQL Server Query Store to Find Top Queries and Regressions"
seo_description: Use SQL Server Query Store to find top CPU and duration queries, identify plan regressions after deployments, and track query performance over time. (152 chars)
screenshots_needed:
  - Get-QueryStoreTopQueries output showing top queries by avg_cpu_ms with query_id, plan_count, and avg_duration_ms columns
  - Second screenshot highlighting a query_id with plan_count > 1 to illustrate a plan regression
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Finding Top Queries and Regressions with SQL Server Query Store

Query Store is the most useful performance feature added to SQL Server in the last decade. It records execution plans and runtime statistics for every query over time, which means you can answer questions that were previously unanswerable: what changed after yesterday's deployment, which query degraded over the last week, and which query has multiple competing plans with very different performance.

Before Query Store, answering "which query got slower after this deployment" required that a DBA happened to have a baseline capture running at exactly the right time. Now the data is always there, retained automatically, queryable after the fact.

## The problem

The plan cache (`sys.dm_exec_query_stats`) only retains a plan as long as it stays in cache. A recompile, a memory pressure event, or a SQL Server restart wipes it. You can't go back in time and ask "what was this query's performance like three days ago."

Query Store retains this history — plans, runtime stats, wait stats per query — with configurable retention periods (default 30 days). That makes it genuinely useful for post-incident analysis, regression detection, and trend monitoring.

The challenge is that the Query Store DMVs (`sys.query_store_query`, `sys.query_store_plan`, `sys.query_store_runtime_stats`) are verbose. The script in this repo joins them into a single usable output ranked by the metrics that matter.

## First: verify Query Store is enabled

Query Store is off by default on databases created before SQL Server 2022 (it's on by default in SQL Server 2022 and Azure SQL Database). Check first:

```sql
SELECT name, is_query_store_on
FROM sys.databases
WHERE name = DB_NAME();
```

If `is_query_store_on = 0`, enable it:

```sql
ALTER DATABASE [YourDatabase]
SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,       -- flush interval: 15 min is a good balance
    INTERVAL_LENGTH_MINUTES = 60,            -- aggregation window: hourly
    MAX_STORAGE_SIZE_MB = 1000,              -- adjust based on available disk
    QUERY_CAPTURE_MODE = AUTO,               -- AUTO skips trivial/infrequent queries
    SIZE_BASED_CLEANUP_MODE = AUTO           -- auto-clean when near capacity
);
```

After enabling, Query Store starts collecting data immediately — but you'll need to wait at least a few hours for meaningful trends to appear.

## The script

```sql
SELECT TOP 50
    q.query_id,
    qt.query_sql_text,
    COUNT(DISTINCT p.plan_id)                               AS plan_count,
    SUM(rs.count_executions)                                AS total_executions,
    AVG(rs.avg_cpu_time)        / 1000.0                   AS avg_cpu_ms,
    MAX(rs.max_cpu_time)        / 1000.0                   AS max_cpu_ms,
    AVG(rs.avg_duration)        / 1000.0                   AS avg_duration_ms,
    MAX(rs.max_duration)        / 1000.0                   AS max_duration_ms,
    AVG(rs.avg_logical_io_reads)                           AS avg_logical_reads,
    AVG(rs.avg_rowcount)                                   AS avg_rows_returned,
    MIN(rs.first_execution_time)                           AS first_seen,
    MAX(rs.last_execution_time)                            AS last_seen
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt
    ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p
    ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs
    ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval rsi
    ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE rsi.start_time > DATEADD(hour, -24, GETDATE())  -- last 24 hours
  AND q.is_internal_query = 0
GROUP BY q.query_id, qt.query_sql_text
ORDER BY AVG(rs.avg_cpu_time) DESC;
```

## How to run it from the repo

```powershell
# Top queries by CPU in the last 24 hours
.\run.ps1 Get-QueryStoreTopQueries

# Against a specific database
.\run.ps1 Get-QueryStoreTopQueries -Database YourDatabaseName

# Extend the window to 7 days
.\run.ps1 Get-QueryStoreTopQueries -Database YourDatabaseName -Hours 168

# Save for comparison
.\run.ps1 Get-QueryStoreTopQueries -Database YourDatabaseName -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `query_id` | Stable identifier for this query text. The same `query_id` persists across restarts and plan changes. |
| `query_sql_text` | The parameterised query text. Ad-hoc queries appear as-is; stored procedures appear as the internal call. |
| `plan_count` | How many distinct execution plans exist for this query. **1 = stable plan. 2+ = plan instability or regression.** |
| `total_executions` | Execution count within the time window. |
| `avg_cpu_ms` | Average CPU time per execution in milliseconds. This is your primary ranking metric for CPU-intensive queries. |
| `max_cpu_ms` | Worst single execution CPU time — helps spot occasional very slow runs. |
| `avg_duration_ms` | Average elapsed time per execution. Includes waits (I/O, locks) — higher than `avg_cpu_ms` if the query is I/O or lock bound. |
| `avg_logical_reads` | Average logical reads (buffer pool touches) per execution. High values point to missing indexes or large scans. |
| `first_seen` / `last_seen` | When this query first and most recently executed in the window. |

## Spotting plan regressions

`plan_count > 1` is the regression signal. A query that has two or more plans has experienced a plan change — and one of those plans is almost certainly worse than the other.

To investigate a query with `plan_count > 1`:

```sql
-- Find both plans and their performance
SELECT
    p.plan_id,
    p.engine_version,
    p.compatibility_level,
    p.is_forced_plan,
    AVG(rs.avg_cpu_time)    / 1000.0    AS avg_cpu_ms,
    AVG(rs.avg_duration)    / 1000.0    AS avg_duration_ms,
    SUM(rs.count_executions)            AS executions,
    MIN(rs.first_execution_time)        AS plan_first_used,
    MAX(rs.last_execution_time)         AS plan_last_used,
    TRY_CAST(p.query_plan AS XML)       AS query_plan
FROM sys.query_store_plan p
JOIN sys.query_store_runtime_stats rs
    ON rs.plan_id = p.plan_id
WHERE p.query_id = [your_query_id]   -- from the top queries output
GROUP BY p.plan_id, p.engine_version, p.compatibility_level,
         p.is_forced_plan, p.query_plan
ORDER BY avg_cpu_ms DESC;
```

The plan with the higher `avg_cpu_ms` is the bad plan. Compare it against the good plan in SSMS — click the `query_plan` XML to open the graphical plan and see where they diverge.

**If the bad plan appeared after a deployment**, that's your regression. Common causes:
- Statistics updated mid-deploy changed the optimiser's cardinality estimates
- A schema change (new index, modified column) changed the plan landscape
- Auto-parameterisation produced a different plan for a different parameter value (parameter sniffing)

## Forcing a good plan

Once you've identified the good plan ID (`good_plan_id`) and the query (`query_id`), you can force Query Store to always use it:

```sql
EXEC sys.sp_query_store_force_plan
    @query_id  = [query_id],
    @plan_id   = [good_plan_id];
```

This is a tactical fix — the query always uses the forced plan regardless of parameters or statistics. It's appropriate when:
- You need to restore performance immediately
- You're waiting for a permanent fix (index, statistics update, code change) to deploy

Remove the forced plan once the permanent fix is in place:

```sql
EXEC sys.sp_query_store_unforce_plan
    @query_id = [query_id],
    @plan_id  = [good_plan_id];
```

## Using Query Store for post-deployment checks

After any significant deployment, run:

```powershell
.\run.ps1 Get-QueryStoreTopQueries -Database YourDatabaseName -Hours 2
```

Compare against a pre-deployment baseline saved to CSV. Look for:
- Queries that jumped up in `avg_cpu_ms` or `avg_duration_ms`
- Queries that were not in the top 50 before that now are
- Queries with `plan_count` that increased (new plan appeared post-deploy)

## Query Store configuration to review

The defaults work but aren't optimal for all workloads. Check the current configuration:

```sql
SELECT
    desired_state_desc,
    actual_state_desc,
    query_capture_mode_desc,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    current_storage_size_mb
FROM sys.database_query_store_options;
```

Key settings to adjust:
- `MAX_STORAGE_SIZE_MB` — default 100 MB fills up quickly on busy servers. Increase to 500–2000 MB.
- `STALE_QUERY_THRESHOLD_DAYS` — default 30 days. Increase to 90 for better trend analysis.
- `QUERY_CAPTURE_MODE = AUTO` — skips trivial queries. Better than `ALL` for most workloads.
- `SIZE_BASED_CLEANUP_MODE = AUTO` — removes oldest data when near capacity. Keep this on.

If Query Store hits its storage limit, it switches to READ_ONLY mode and stops collecting. Check `actual_state_desc` regularly or after any performance incident.

## Related scripts

- [`Get-StatisticsHealth`](../statistics-health/index.md) — stale statistics trigger plan regressions; check stats after identifying a regressed query
- [`Get-MissingIndexes`](../missing-indexes/index.md) — high `avg_logical_reads` in Query Store output points here
- [`Get-WaitStatistics`](../wait-statistics/index.md) — Query Store shows CPU and duration; wait stats show what queries are *waiting* on

## Get the scripts

The full script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-QueryStoreTopQueries.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-QueryStoreTopQueries.sql)

---

## SEO

**Focus keyphrase:** SQL Server Query Store top queries

**Meta description** (152 chars — target 150–160):  
Use SQL Server Query Store to find top CPU and duration queries, identify plan regressions after deployments, and track query performance over time.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `query-store-top-queries.png` | Get-QueryStoreTopQueries output showing queries ranked by avg_cpu_ms with plan_count column visible | Query Store top queries output |
| `query-store-regression.png` | Same output filtered to a query_id with plan_count of 2, showing two plans with very different avg_cpu_ms values | Query Store plan regression |
