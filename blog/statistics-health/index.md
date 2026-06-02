---
title: "Script: Finding and Fixing Stale SQL Server Statistics"
slug: sql-server-statistics-health
published: 
published_url: 
status: draft
category: performance
tags: [statistics, query-plans, performance, maintenance]
scripts:
  - sql/performance/Get-StatisticsHealth.sql
seo_keyphrase: SQL Server stale statistics
seo_title: "Finding and Fixing Stale SQL Server Statistics"
seo_description: Find stale, low-sample-rate, and never-updated statistics across your SQL Server databases. Includes the UPDATE STATISTICS command for every finding in the output. (166 chars — trim)
screenshots_needed:
  - Get-StatisticsHealth output showing stale statistics with last_updated, rows_sampled_pct, and the ready-to-run update_statement column
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Finding and Fixing Stale SQL Server Statistics

Stale statistics are responsible for more slow queries than most DBAs realise. When the query optimiser builds a plan, it estimates how many rows a filter will return based on statistics histograms. If those statistics are months out of date on a fast-changing table, the estimate is wrong — and a wrong estimate produces a wrong plan. A nested loop where a hash join was needed. A scan where a seek would work. A serial plan where parallelism would help.

The frustrating part is that the query itself is correct. The data is right. The only thing wrong is that SQL Server's picture of the data is stale, and queries run slow in a way that's genuinely difficult to diagnose without checking statistics age and sample rates.

## The problem

SQL Server updates statistics automatically — but only up to a point. The default threshold for triggering an auto-update is when roughly 20% of a table's rows change. On a table with 10 million rows, that's 2 million modifications before SQL Server refreshes the statistics. If that table has heavy insert-delete churn, the statistics can be significantly stale while still below the trigger threshold.

There's also a sample rate problem. When auto-update runs, it doesn't read the entire table — it takes a sample. On large tables, that sample might be 10% or less of the actual rows. Statistics built on a 10% sample of a skewed data distribution will produce estimates that are systematically wrong for queries that hit the tail of the distribution.

The result: queries that were fast last month are slow this month, without any code change, because the data distribution changed and the statistics haven't caught up.

## The script

```sql
SELECT
    OBJECT_SCHEMA_NAME(s.object_id)         AS schema_name,
    OBJECT_NAME(s.object_id)                AS table_name,
    s.name                                  AS stats_name,
    s.auto_created,
    s.user_created,
    sp.last_updated,
    DATEDIFF(day, sp.last_updated, GETDATE()) AS days_since_update,
    sp.rows,
    sp.rows_sampled,
    CAST(100.0 * sp.rows_sampled
         / NULLIF(sp.rows, 0) AS DECIMAL(5,1))  AS rows_sampled_pct,
    sp.modification_counter,
    CAST(100.0 * sp.modification_counter
         / NULLIF(sp.rows, 0) AS DECIMAL(5,1))  AS modification_pct,
    CASE
        WHEN sp.last_updated IS NULL                          THEN 'NEVER UPDATED'
        WHEN sp.modification_counter > sp.rows * 0.20        THEN 'STALE - EXCEEDS 20% THRESHOLD'
        WHEN DATEDIFF(day, sp.last_updated, GETDATE()) > 30
             AND sp.modification_counter > sp.rows * 0.05    THEN 'AGING - REVIEW'
        WHEN sp.rows_sampled < sp.rows * 0.10
             AND sp.rows > 10000                             THEN 'LOW SAMPLE RATE'
        ELSE 'OK'
    END                                     AS status,
    'UPDATE STATISTICS ['
        + OBJECT_SCHEMA_NAME(s.object_id)
        + '].['
        + OBJECT_NAME(s.object_id)
        + '] ['
        + s.name
        + '] WITH FULLSCAN;'                AS update_statement
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
  AND sp.rows > 0
ORDER BY
    CASE WHEN sp.last_updated IS NULL THEN 0
         WHEN sp.modification_counter > sp.rows * 0.20 THEN 1
         ELSE 2 END,
    sp.modification_counter DESC;
```

## How to run it from the repo

```powershell
# Check current database
.\run.ps1 Get-StatisticsHealth

# Against a specific database
.\run.ps1 Get-StatisticsHealth -Database YourDatabaseName

# Save to CSV to track over time
.\run.ps1 Get-StatisticsHealth -Database YourDatabaseName -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `stats_name` | The statistics object name. Index statistics share the name of the index. Auto-created stats have generated names like `_WA_Sys_...`. |
| `last_updated` | When these statistics were last refreshed. NULL means they've never been updated. |
| `days_since_update` | Age of the statistics in days. |
| `rows` | Number of rows in the table at the time of the last update. |
| `rows_sampled` | How many rows were actually read to build the histogram. |
| `rows_sampled_pct` | The sample rate. 100% means FULLSCAN was used. Below 10% on large tables is often not enough for skewed data. |
| `modification_counter` | Number of row changes (inserts, updates, deletes) since the last statistics update. |
| `modification_pct` | Modifications as a percentage of the row count. Above 20% means the auto-update threshold has been crossed but auto-update hasn't run yet, or auto-update is off. |
| `status` | Quick classification: `NEVER UPDATED`, `STALE`, `AGING`, `LOW SAMPLE RATE`, or `OK`. |
| `update_statement` | Ready-to-run `UPDATE STATISTICS ... WITH FULLSCAN` command. Copy this and run it to fix the finding immediately. |

## What to look for

**`NEVER UPDATED`** — a statistics object that has never been updated at all. This happens on newly created tables or indexes that haven't had any data yet when auto-update triggered, or on databases that had auto-update stats turned off. These need updating first.

**`STALE - EXCEEDS 20% THRESHOLD`** — more than 20% of rows have changed since the last update. The query optimiser may already have stale statistics cached for plans using this table. Priority fix.

**`LOW SAMPLE RATE`** — statistics were last updated with a low sample rate. For tables with non-uniform data distributions (e.g. dates with heavy recent skew, status columns with heavily imbalanced values), a low sample rate produces inaccurate histograms and poor estimates.

**Sort order** — the script sorts by urgency: `NEVER UPDATED` first, then `STALE`, then the rest ordered by modification count descending. The top rows are your priority.

## How auto-update statistics works (and where it falls short)

SQL Server's automatic statistics update fires when:
- The table was empty and now has rows, and a query touches it
- The modification counter crosses 20% of the row count (the "classic" threshold)
- For SQL Server 2016+ with compatibility level 130+: a dynamic threshold applies — the trigger fires sooner on very large tables (roughly at `sqrt(1000 * rows)` modifications)

**The dynamic threshold matters.** Before compat level 130, a 100-million-row table needed 20 million modifications before auto-update fired. With the dynamic threshold, it fires at around 316,000 modifications — much more responsive. If your databases are on older compat levels, upgrading the compat level (not the SQL Server version, just the database compat level setting) can significantly improve statistics freshness.

**Auto-update uses a sample.** For large tables, the sample rate can be well below 10%. This is efficient but imprecise. If your data distribution is skewed — and most production data has some skew — a low sample rate produces systematically wrong estimates for the rows that fall in the tail.

**Auto-update is asynchronous by default** — it fires in the background after the statistics are found to be stale, which means the query that triggered it runs with the stale stats while the update happens in parallel. The next execution gets the fresh stats. This is usually fine, but means there's always a window of one "bad" execution.

## When FULLSCAN is worth it

The `update_statement` column always generates a `FULLSCAN` command. FULLSCAN reads the entire table to build the statistics histogram — the most accurate possible update, but also the most expensive.

Use FULLSCAN when:
- The table has heavily skewed data (recent dates, status columns with dominant values)
- The default sample rate is below 20–30% and queries are producing bad estimates
- You're updating stats as part of a performance investigation and want a clean baseline
- The table is being read primarily during off-peak hours and the FULLSCAN cost is acceptable

Don't use FULLSCAN when:
- The table is 500 GB and the FULLSCAN would take 30 minutes during a maintenance window where you're also running other maintenance tasks
- The data distribution is uniform — in that case, a sample is nearly as accurate

For very large tables with skewed data and a need for accurate histograms, consider filtered statistics or incremental statistics (Enterprise Edition) as alternatives to a full-table FULLSCAN.

## What to do with the output

1. Copy the `update_statement` value for any statistics marked `NEVER UPDATED` or `STALE - EXCEEDS 20% THRESHOLD` and run them. These are your immediate fixes.

2. For `LOW SAMPLE RATE` findings on tables you know have skewed data, run the FULLSCAN update and then test the affected queries — you'll often see immediate plan improvements.

3. For a recurring maintenance strategy: add statistics maintenance to your weekly maintenance window. The Ola Hallengren maintenance solution is the standard choice for this — it updates statistics intelligently based on modification counts and sample rates.

4. Review compat level — if your databases are below 130 and you're running SQL Server 2016+, raising the compat level enables the dynamic auto-update threshold and often reduces statistics staleness without any other changes.

## Related scripts

- [`Get-MissingIndexes`](../missing-indexes/index.md) — stale statistics and missing indexes are often found together
- [`Get-WaitStatistics`](../wait-statistics/index.md) — `RESOURCE_SEMAPHORE` (bad memory grants) often traces back to stale statistics producing bad estimates

## Get the scripts

The full script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-StatisticsHealth.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-StatisticsHealth.sql)

---

## SEO

**Focus keyphrase:** SQL Server stale statistics

**Meta description** (166 chars — trim to 160 before publishing):  
Find stale, low-sample-rate, and never-updated statistics across your SQL Server databases. Includes the UPDATE STATISTICS command for every finding in the output.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `statistics-health-output.png` | Get-StatisticsHealth output showing STALE and NEVER UPDATED rows with update_statement column containing ready-to-run SQL | Statistics health check output |
