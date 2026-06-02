---
title: "Script: Finding Unused and Underused SQL Server Indexes"
slug: sql-server-unused-indexes
published: 
published_url: 
status: draft
category: performance
tags: [indexes, performance, maintenance, unused-indexes, write-overhead]
scripts:
  - sql/performance/Get-UnusedIndexes.sql
  - sql/performance/Get-IndexUsageStats.sql
  - powershell/reporting/Get-IndexUsageStats.ps1
seo_keyphrase: SQL Server unused indexes
seo_title: "Finding Unused SQL Server Indexes That Are Slowing Down Writes"
seo_description: Unused SQL Server indexes cost write performance on every INSERT, UPDATE, and DELETE without benefiting any query. Here's how to find and safely remove them. (158 chars)
screenshots_needed:
  - Get-UnusedIndexes output showing index_name, write_count, total_reads (zero), size_mb, and drop_statement columns
  - Get-IndexUsageStats output showing WRITE_ONLY usage_pattern rows for high-overhead indexes
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Finding Unused SQL Server Indexes That Are Slowing Down Writes

Every non-clustered index on a table must be maintained by SQL Server on every `INSERT`, `UPDATE`, and `DELETE`. SQL Server writes to the table, then updates every index. A table with 12 non-clustered indexes requires 12 index updates for every row changed. Some of those indexes are essential — they serve real queries. Others haven't been used by a single query since the last SQL Server restart.

Those unused indexes are pure overhead. They slow down writes, consume disk space, use buffer pool memory, extend backup time, and increase index fragmentation maintenance work — while providing zero benefit to any query.

Every index you remove from an unused list is a write performance win.

## The problem

Indexes accumulate. A developer adds one to fix a slow query. A consultant adds three during a performance engagement. An index maintenance job that used to run changes to run less often. Years later, the workload has shifted, some of those indexes serve queries that no longer run, but nobody removes them.

There's no built-in alert when an index stops being used. The only way to find them is to query `sys.dm_db_index_usage_stats` — which tracks reads and writes per index since the last SQL Server restart.

## The scripts

### Get-UnusedIndexes.sql — zero-read, non-zero-write indexes

```sql
SELECT
    OBJECT_SCHEMA_NAME(i.object_id)    AS schema_name,
    OBJECT_NAME(i.object_id)           AS table_name,
    i.name                             AS index_name,
    i.type_desc,
    i.is_unique,
    ISNULL(s.user_seeks,   0)          AS seeks,
    ISNULL(s.user_scans,   0)          AS scans,
    ISNULL(s.user_lookups, 0)          AS lookups,
    ISNULL(s.user_seeks,0) + ISNULL(s.user_scans,0)
        + ISNULL(s.user_lookups,0)     AS total_reads,
    ISNULL(s.user_updates, 0)          AS write_count,
    ISNULL(p.rows,         0)          AS table_rows,
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10,2))  AS size_mb,
    'DROP INDEX ' + QUOTENAME(i.name)
        + ' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id))
        + '.' + QUOTENAME(OBJECT_NAME(i.object_id)) + ';'   AS drop_statement
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT JOIN sys.dm_db_index_usage_stats s
    ON s.object_id = i.object_id AND s.index_id = i.index_id AND s.database_id = DB_ID()
WHERE i.type_desc           <> 'HEAP'
  AND i.is_primary_key       = 0
  AND i.is_unique_constraint = 0
  AND t.is_ms_shipped        = 0
  AND ISNULL(s.user_seeks,0) + ISNULL(s.user_scans,0) + ISNULL(s.user_lookups,0) = 0
  AND ISNULL(s.user_updates, 0) > 0
GROUP BY i.object_id, i.index_id, i.name, i.type_desc, i.is_unique,
         s.user_seeks, s.user_scans, s.user_lookups, s.user_updates, p.rows
ORDER BY write_count DESC, size_mb DESC;
```

### Get-IndexUsageStats.sql — all indexes with usage pattern classification

```sql
SELECT
    DB_NAME(ius.database_id)                       AS database_name,
    OBJECT_SCHEMA_NAME(ius.object_id, ius.database_id) AS schema_name,
    OBJECT_NAME(ius.object_id, ius.database_id)    AS table_name,
    ius.index_id,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.user_seeks + ius.user_scans + ius.user_lookups AS total_reads,
    CASE
        WHEN ius.user_seeks + ius.user_scans + ius.user_lookups = 0
             AND ius.user_updates > 0 THEN 'WRITE_ONLY'
        WHEN ius.user_scans > ius.user_seeks * 10  THEN 'SCAN_HEAVY'
        ELSE 'NORMAL'
    END                                            AS usage_pattern,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_update
FROM sys.dm_db_index_usage_stats AS ius
WHERE ius.database_id > 4
ORDER BY ius.user_updates DESC, total_reads DESC;
```

## How to run it from the repo

```powershell
# Unused indexes in the current database (run in context of target DB)
.\run.ps1 Get-UnusedIndexes -Database YourDatabaseName

# All indexes with usage pattern classification
.\run.ps1 Get-IndexUsageStats

# Save to CSV for review
.\run.ps1 Get-UnusedIndexes -Database YourDatabaseName -OutputFormat Csv
```

## Reading the output — Get-UnusedIndexes

| Column | What it means |
|--------|---------------|
| `schema_name` / `table_name` | Where the index lives. |
| `index_name` | The index name. |
| `type_desc` | `NONCLUSTERED` in most cases — clustered indexes and heaps are excluded from this script. |
| `is_unique` | Whether the index enforces uniqueness. Unique non-clustered indexes have a data integrity purpose beyond query optimisation — be more careful dropping these. |
| `seeks` / `scans` / `lookups` | All zero for unused indexes — this is the filter condition. |
| `total_reads` | Sum of seeks + scans + lookups. Zero. |
| `write_count` | How many times this index has been updated (INSERTs, UPDATEs, DELETEs on the table). A high number here means the index is paying a significant write cost. |
| `size_mb` | How much disk space (and buffer pool memory) the index consumes. |
| `drop_statement` | Ready-to-run `DROP INDEX` statement. Review before executing. |

## Reading the output — Get-IndexUsageStats

| `usage_pattern` value | What it means |
|-----------------------|---------------|
| `WRITE_ONLY` | Zero reads, non-zero writes. Prime drop candidate (same as Get-UnusedIndexes result). |
| `SCAN_HEAVY` | Being used (non-zero reads), but mostly via full index scans rather than seeks. Scans are less efficient than seeks and may indicate the index isn't covering the workload well, or there's a missing more-selective index. |
| `NORMAL` | Being used normally — mix of seeks. |

## Critical caveats before dropping anything

**Stats reset on SQL Server restart.** `sys.dm_db_index_usage_stats` accumulates from the moment SQL Server started. On a server that was restarted last week, you have only one week of data. An index that serves a monthly batch job won't have any reads in that window — but dropping it breaks the batch job.

**Best practice: wait for a representative period.** Before using unused index data to make drop decisions, ensure the server has been running long enough to capture your full workload cycle. For most OLTP systems, 2–4 weeks covers all daily and weekly patterns. For systems with monthly jobs, 6–8 weeks is safer. Check `sys.dm_os_sys_info.sqlserver_start_time` to see how long the current stats have been accumulating.

**Do not drop without checking all environments.** An index that's unused on production might be critical on a copy of production used for month-end reporting. Check your reporting environments, DR servers, and any other copies of the database.

**Unique non-clustered indexes** — even if they show zero reads, they may enforce data integrity constraints that have never been violated. A `UNIQUE` index with zero reads isn't useless — it's protecting data. Review with the application owner before dropping.

**Filtered indexes** — indexes with a WHERE clause may serve a specific filtered query that's rare but important. Check the filter definition before deciding.

## Safe removal process

1. Run `Get-UnusedIndexes` after a representative workload period
2. Sort by `size_mb DESC` — larger indexes have larger overhead, prioritise those
3. For each candidate, verify: check query history, check all environments, check if unique
4. Test the drop in a non-production environment
5. Drop one index at a time and monitor write performance before and after
6. Keep the `drop_statement` in a script so you can recreate if needed

```sql
-- BEFORE dropping: script the index definition (run this first)
SELECT
    'CREATE ' + CASE WHEN i.is_unique = 1 THEN 'UNIQUE ' ELSE '' END + 'NONCLUSTERED INDEX ['
    + i.name + '] ON [' + SCHEMA_NAME(t.schema_id) + '].[' + t.name + '] ('
    + key_cols.cols + ')' AS create_statement
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
CROSS APPLY (
    SELECT STRING_AGG('[' + c.name + '] ' + CASE ic.is_descending_key WHEN 1 THEN 'DESC' ELSE 'ASC' END, ', ')
           WITHIN GROUP (ORDER BY ic.key_ordinal) AS cols
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
) key_cols
WHERE i.name = 'YourIndexName' AND t.name = 'YourTableName';
```

Then drop:

```sql
DROP INDEX [IndexName] ON [schema].[TableName];
```

## Related scripts

- [`Get-MissingIndexes`](../missing-indexes/index.md) — the complement: indexes that should exist but don't
- [`Get-IndexFragmentation`](../index-fragmentation/index.md) — if you're dropping unused indexes, also fix fragmentation on the remaining ones
- [`Get-WaitStatistics`](../wait-statistics/index.md) — high `PAGEIOLATCH_SH` alongside many indexes may indicate index bloat

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-UnusedIndexes.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-UnusedIndexes.sql)
- [`sql/performance/Get-IndexUsageStats.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-IndexUsageStats.sql)

---

## SEO

**Focus keyphrase:** SQL Server unused indexes

**Meta description** (158 chars — target 150–160):  
Unused SQL Server indexes cost write performance on every INSERT, UPDATE, and DELETE without benefiting any query. Here's how to find and safely remove them.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `unused-indexes-output.png` | Get-UnusedIndexes output showing index_name, write_count, total_reads of zero, size_mb, and drop_statement columns | Unused indexes with write overhead |
| `index-usage-stats-output.png` | Get-IndexUsageStats output showing WRITE_ONLY usage_pattern rows for several large indexes | Index usage pattern classification |
