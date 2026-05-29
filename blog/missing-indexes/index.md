---
title: Finding Missing Indexes in SQL Server
slug: sql-server-missing-indexes
published: 
status: draft
category: performance
tags: [indexes, performance, dmv, query-tuning]
scripts:
  - sql/performance/Get-MissingIndexes.sql
  - powershell/reporting/Get-MissingIndexes.ps1
seo_keyphrase:    SQL Server missing indexes
seo_title:        Finding Missing Indexes in SQL Server
seo_description:  Find SQL Server missing indexes ranked by impact score. Prioritise suggestions, avoid index bloat, and create the right indexes for your workload. (146 chars)
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Finding Missing Indexes in SQL Server

Every time SQL Server builds an execution plan that could be improved with a better index, it makes a note of it. These notes accumulate in memory and are queryable through the `sys.dm_db_missing_index_*` DMVs. Combined into a single ranked list with an impact score, this is one of the fastest wins in SQL Server performance tuning.

The catch is that SQL Server's suggestions are per-query, not per-workload. It will suggest an index for every query that needed one, even if that means overlapping indexes, or indexes that conflict with each other. Acting on every suggestion blindly creates index bloat. This post covers how to read and prioritise the list sensibly.

## The problem

Slow queries are usually slow because they're scanning when they could be seeking. A table scan reads every row; an index seek reads only the rows that match. On a large table the difference is milliseconds vs minutes. SQL Server's query optimiser knows when it couldn't find a suitable index and records what it would have needed.

The challenge is acting on that information without creating 50 new indexes that collectively slow down write performance. Index maintenance has a cost: every INSERT, UPDATE, and DELETE on a table must also update all its indexes. The goal is to identify the highest-impact, non-overlapping indexes from the noise.

## The script

```sql
SELECT
    mid.statement                                                                       AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.user_scans,
    CAST(migs.avg_total_user_cost   AS DECIMAL(10,2))                                  AS avg_query_cost,
    CAST(migs.avg_user_impact       AS DECIMAL(5,1))                                   AS avg_improvement_pct,
    CAST(migs.user_seeks * migs.avg_total_user_cost * migs.avg_user_impact / 100.0
         AS DECIMAL(14,0))                                                              AS impact_score,
    'CREATE INDEX [ix_missing_' + REPLACE(REPLACE(ISNULL(mid.equality_columns,'') +
        ISNULL('_' + mid.inequality_columns,''), '[',''), ']','') + ']'
    + ' ON ' + mid.statement
    + ' (' + ISNULL(mid.equality_columns,'')
    + CASE WHEN mid.inequality_columns IS NOT NULL THEN
        CASE WHEN mid.equality_columns IS NOT NULL THEN ', ' ELSE '' END
        + mid.inequality_columns ELSE '' END + ')'
    + CASE WHEN mid.included_columns IS NOT NULL
        THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END
    + ';'                                                                               AS suggested_statement
FROM sys.dm_db_missing_index_group_stats AS migs
JOIN sys.dm_db_missing_index_groups      AS mig  ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details     AS mid  ON mig.index_handle  = mid.index_handle
ORDER BY impact_score DESC;
```

## How to run it from the repo

```powershell
# Table output ranked by impact_score
.\run.ps1 Get-MissingIndexes

# Save as CSV — useful for review and before/after comparison
.\run.ps1 Get-MissingIndexes -OutputFormat Csv

# Against a named instance
.\run.ps1 Get-MissingIndexes -ServerInstance MYSERVER\INST01 -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `table_name` | The table needing the index (includes schema and database) |
| `equality_columns` | Columns used in `WHERE col = value` predicates |
| `inequality_columns` | Columns used in range predicates (`>`, `<`, `BETWEEN`) |
| `included_columns` | Non-key columns SQL Server wants in the INCLUDE clause to avoid key lookups |
| `user_seeks` | How many times an index seek would have been used if this index existed |
| `avg_query_cost` | Estimated cost of the queries that triggered this suggestion |
| `avg_improvement_pct` | Estimated percentage improvement if this index existed |
| `impact_score` | `user_seeks × avg_query_cost × avg_improvement_pct / 100` — a composite priority score |
| `suggested_statement` | A generated `CREATE INDEX` statement — a starting point, not a final answer |

The `impact_score` is the primary sort key. It combines how often the index would be used (`user_seeks`), how expensive the queries are (`avg_query_cost`), and how much better they would be (`avg_improvement_pct`). A suggestion with 10,000 seeks on a cheap query scores lower than one with 100 seeks on an expensive query.

## How to prioritise the suggestions

**Start from the top.** The highest `impact_score` entries are where query time is being lost most. Don't try to act on the whole list at once.

**Look for overlapping suggestions.** SQL Server might suggest `(CustomerID)`, `(CustomerID, OrderDate)`, and `(CustomerID, OrderDate, StatusID)` separately. These overlap — a single composite index covering `(CustomerID, OrderDate, StatusID)` often satisfies all three. Consolidate before creating.

**Check existing indexes first.** Before creating a suggested index, look at the table's existing indexes. The suggestion might be nearly covered by an existing index with a small modification.

**Review the `included_columns`.** SQL Server is trying to avoid a key lookup (where SQL Server finds the row via the index key, then has to go back to the base table to fetch other columns). Adding the right INCLUDE columns makes the index self-sufficient for those queries. But don't blindly include everything — wide included columns increase index size.

**Watch out for write-heavy tables.** If a table is INSERT/UPDATE-heavy, adding indexes costs write performance. Check `Get-IndexUsageStats.sql` to see the existing write overhead on a table before adding to it.

## What to do with the suggested_statement

The `suggested_statement` column generates a `CREATE INDEX` statement, but the name is auto-generated and may be long. Before running it:

1. Give the index a meaningful name following your naming convention
2. Add `ONLINE = ON` if the table is in production and you can't afford a lock
3. Test on a non-production copy first
4. Run the query that triggered the suggestion before and after — verify the improvement is real

```sql
-- Example: generated statement (rename before using)
CREATE INDEX [ix_missing_CustomerID_OrderDate]
ON [dbo].[Orders] ([CustomerID], [OrderDate])
INCLUDE ([StatusID], [TotalAmount]);

-- Production-safe with online rebuild:
CREATE INDEX [ix_Orders_CustomerID_OrderDate]
ON [dbo].[Orders] ([CustomerID], [OrderDate])
INCLUDE ([StatusID], [TotalAmount])
WITH (ONLINE = ON, SORT_IN_TEMPDB = ON);
```

## Important caveats

**These counters reset on restart.** The DMV data accumulates since the last SQL Server restart (or since the plan was last compiled). On a freshly restarted server the list will be sparse. On a server that's been up for 6 months it's a good signal.

**SQL Server optimises for individual queries, not the workload.** It might suggest conflicting indexes for two different queries. Your job is to find the index that serves the workload, not implement every suggestion individually.

**High `user_scans` with low `user_seeks` is a different problem.** If a suggestion has many scans but few seeks, the query is retrieving large portions of the table. An index might help but the bigger fix may be rewriting the query or improving the WHERE clause selectivity.

## Related scripts in this repo

- [`Get-IndexUsageStats.sql`](../sql/performance/Get-IndexUsageStats.sql) — see how existing indexes are used (seek vs scan vs update ratio)
- [`Get-IndexFragmentation.sql`](../sql/monitoring/Get-IndexFragmentation.sql) — check fragmentation on existing indexes before adding more
- [`Get-TopIoQueries.sql`](../sql/performance/Get-TopIoQueries.sql) — the queries with the highest logical reads are often the ones behind missing index suggestions

## Get the scripts

The full script is available in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-MissingIndexes.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-MissingIndexes.sql)
- [`powershell/reporting/Get-MissingIndexes.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-MissingIndexes.ps1)

---

## SEO

**Focus keyphrase:** SQL Server missing indexes

**Meta description** (146 chars — target 150–160):  
Find SQL Server missing indexes ranked by impact score. Prioritise suggestions, avoid index bloat, and create the right indexes for your workload.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `missing-indexes-output.png` | SQL Server missing indexes DMV query output sorted by impact_score with suggested CREATE INDEX statements | SQL Server missing indexes query output |