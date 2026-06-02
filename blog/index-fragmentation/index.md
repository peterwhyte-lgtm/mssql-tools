---
title: "Script: Diagnosing and Fixing SQL Server Index Fragmentation"
slug: sql-server-index-fragmentation
published: 
published_url: 
status: draft
category: performance
tags: [indexes, fragmentation, maintenance, performance, io]
scripts:
  - sql/monitoring/Get-IndexFragmentation.sql
  - sql/maintenance/Generate-IndexMaintenanceScript.sql
  - powershell/reporting/Get-IndexFragmentation.ps1
seo_keyphrase:    SQL Server index fragmentation
seo_title:        "Script: Diagnosing and Fixing SQL Server Index Fragmentation"
seo_description:  Identify fragmented SQL Server indexes across all databases and generate the right REBUILD or REORGANIZE commands. Includes thresholds, ONLINE considerations, and when to skip it entirely. (192 chars — trim to 160 before publishing)
screenshots_needed:
  - Get-IndexFragmentation output showing avg_fragmentation_pct and recommended_action (REBUILD / REORGANIZE / SKIP) per index
  - Sample of the generated INDEX REBUILD/REORGANIZE script from Generate-IndexMaintenanceScript
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Diagnosing and Fixing SQL Server Index Fragmentation

Index fragmentation is one of those topics where the received wisdom — "rebuild your indexes every weekend" — causes as many problems as it solves. Rebuilding an index that doesn't need it wastes a maintenance window, locks tables on Standard Edition, and generates unnecessary transaction log. Not rebuilding an index that does need it leaves queries doing unnecessary I/O. The goal is to identify and fix the indexes that are actually causing problems, and leave the rest alone.

## The problem

When SQL Server inserts or updates rows, it maintains index order by splitting pages. Over time this creates two types of fragmentation. External fragmentation is when pages are out of logical order on disk — the index says page 1 points to page 48, which points to page 3. Sequential reads become random reads, which is expensive on spinning disk (less so on SSD, but not free). Internal fragmentation is when pages are partially full — a page holds 40% of its capacity because it was split and not refilled. More pages means more I/O for the same amount of data.

The practical effect: queries that should be doing efficient range scans start doing more physical reads than necessary. On large tables this shows up as elevated `PAGEIOLATCH_SH` waits.

**When it matters more:** high-volume OLTP tables that take frequent writes and have large range-scan queries. Spinning disk. Tables in the tens of millions of rows.

**When it matters less:** small tables (under a few thousand pages), tables on NVMe SSDs where random I/O is fast, heap tables (which don't have a clustered index to fragment), and read-only databases.

## The diagnostic script

This script scans all online user databases using `LIMITED` scan mode — fast enough for most environments but not as precise as `DETAILED`. It excludes small indexes (under 1,000 pages) where fragmentation is largely irrelevant, and already classifies each index as `REBUILD` or `REORGANIZE` based on the standard thresholds.

```sql
SET NOCOUNT ON;

CREATE TABLE #frag (
    database_name      sysname         NOT NULL,
    schema_name        sysname         NOT NULL,
    table_name         sysname         NOT NULL,
    index_name         sysname         NOT NULL,
    index_type         nvarchar(60)    NOT NULL,
    fragmentation_pct  decimal(5,1)    NOT NULL,
    page_count         bigint          NOT NULL,
    recommended_action varchar(10)     NOT NULL
);

DECLARE @sql nvarchar(max) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #frag
    (database_name, schema_name, table_name, index_name,
     index_type, fragmentation_pct, page_count, recommended_action)
SELECT
    DB_NAME(),
    s.name, t.name, i.name, i.type_desc,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1)),
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN ''REBUILD''
        WHEN ips.avg_fragmentation_in_percent >= 10 THEN ''REORGANIZE''
    END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ips
JOIN sys.indexes AS i ON  ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.tables  AS t ON  i.object_id   = t.object_id
JOIN sys.schemas AS s ON  t.schema_id   = s.schema_id
WHERE i.name IS NOT NULL
  AND ips.page_count                   >= 1000
  AND ips.avg_fragmentation_in_percent >= 10;
'
FROM sys.databases
WHERE state_desc  = 'ONLINE'
  AND database_id > 4;

EXEC sys.sp_executesql @sql;

SELECT
    database_name, schema_name, table_name, index_name,
    index_type, fragmentation_pct, page_count, recommended_action
FROM   #frag
ORDER BY fragmentation_pct DESC;

DROP TABLE #frag;
```

## The fix script — generating maintenance statements

Once you know what's fragmented, the companion script generates the `ALTER INDEX` commands:

```sql
-- Generates REBUILD / REORGANIZE statements across all user databases.
-- Review the maintenance_statement column and execute in a maintenance window.
-- Remove WITH (ONLINE = ON) on Standard Edition.

-- Thresholds are DECLARE'd at the top — adjust if needed
DECLARE @rebuild_pct  DECIMAL(5,1) = 30.0;
DECLARE @reorg_pct    DECIMAL(5,1) = 10.0;
DECLARE @min_pages    INT          = 1000;

-- [Full script in repo: sql/maintenance/Generate-IndexMaintenanceScript.sql]
```

> **Tip:** Run the diagnostic first to understand the scope, then run the generator to produce the actual DDL. This way you can review and schedule the maintenance rather than running a blind loop.

## How to run from the repo

```powershell
# Fragmentation diagnostic — saves to CSV
.\run.ps1 Get-IndexFragmentation

# View results in the web UI
.\run.ps1 Get-IndexFragmentation -OutputFormat Csv

# Generate the maintenance statements
.\run.ps1 Generate-IndexMaintenanceScript
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `fragmentation_pct` | Percentage of pages out of order. The primary sort column. |
| `page_count` | Number of 8KB pages in the index. Fragmentation on a 1,200-page index matters more than on a 1,000-page index. |
| `recommended_action` | `REBUILD` (≥30%) or `REORGANIZE` (10–29%). See below for when to override. |
| `index_type` | `CLUSTERED` fragmentation affects all reads of that table. `NONCLUSTERED` affects only queries using that index. |

## REBUILD vs REORGANIZE — what actually happens

**REORGANIZE** defragments the leaf level of the index in place, page by page. It's always online, can be interrupted and restarted, and is suitable for lower fragmentation. The downside: it doesn't update statistics, and it can't compact the index below the current fill factor.

**REBUILD** drops and recreates the index with a fresh fill factor, updates statistics as a side effect, and reclaims all free space. On **Enterprise and Developer editions** with `WITH (ONLINE = ON)`, the table stays accessible throughout. On **Standard Edition**, a rebuild takes a schema modification lock — the table is inaccessible for the duration. For large tables this can be minutes to hours.

**Rule of thumb:**
- 10–30% fragmentation → REORGANIZE
- >30% fragmentation → REBUILD (online if available)
- >30% fragmentation, Standard Edition, large table, no window → REORGANIZE instead and accept the trade-off

## What to look for

**Clustered index on a high-write table with >30% fragmentation** — This is the highest-impact finding. Every query against this table that does a range scan is affected. Fix this first.

**Many indexes on the same table, all showing high fragmentation** — Indicates the table is taking a lot of writes. Consider whether all those indexes are necessary — `Get-UnusedIndexes.sql` can identify which ones aren't being read.

**Fragmentation is back to 80% a week after the last rebuild** — The index is fragmenting faster than the maintenance cycle can keep up. Either increase the fill factor (leaves more free space per page, reducing splits), increase maintenance frequency, or investigate whether the write pattern can be changed.

**`page_count` is between 1,000 and 5,000 with high fragmentation** — Borderline. Fixing this won't have much impact. Prioritise indexes with 10,000+ pages.

## The ONLINE option — know your edition

```sql
-- Enterprise / Developer: online rebuild (no table lock)
ALTER INDEX [ix_orders_customer] ON [dbo].[Orders]
    REBUILD WITH (ONLINE = ON);

-- Standard Edition: offline rebuild (table unavailable)
ALTER INDEX [ix_orders_customer] ON [dbo].[Orders]
    REBUILD;

-- Always available — no table lock, lower fragmentation range
ALTER INDEX [ix_orders_customer] ON [dbo].[Orders]
    REORGANIZE;
```

If you're on Standard Edition managing tables with millions of rows, a full REBUILD during business hours is not an option. Reorganize large tables or schedule rebuilds strictly in off-hours windows.

## Gotchas

- **`LIMITED` scan mode can miss some fragmentation.** Use `DETAILED` if you need precise numbers, but expect it to run much longer on large instances.
- **Stats are not updated by REORGANIZE.** If your query plans are stale, you need a separate `UPDATE STATISTICS` pass or use `REBUILD` which handles this automatically.
- **Fragmentation resets after a rebuild, not a restart.** SQL Server restarts don't affect existing fragmentation — the pages are still in the same state on disk.
- **Partitioned indexes:** Each partition can be rebuilt independently. If only one partition is fragmented, there's no need to rebuild the whole index.
- **On SSDs, the threshold for caring shifts upward.** Random I/O is fast on NVMe. Many production environments on all-flash storage only rebuild at >50% fragmentation.

## Related scripts in this repo

- [`Get-IndexUsageStats.sql`](../sql/performance/Get-IndexUsageStats.sql) — which indexes are being used; context before you rebuild
- [`Get-UnusedIndexes.sql`](../sql/performance/Get-UnusedIndexes.sql) — drop candidates: high write cost, zero reads
- [`Get-StatisticsHealth.sql`](../sql/performance/Get-StatisticsHealth.sql) — stale stats are often the real cause of slow queries blamed on fragmentation
- [`Get-MissingIndexes.sql`](../sql/performance/Get-MissingIndexes.sql) — if queries are slow, check for missing indexes before rebuilding existing ones

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-IndexFragmentation.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-IndexFragmentation.sql)
- [`sql/maintenance/Generate-IndexMaintenanceScript.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/maintenance/Generate-IndexMaintenanceScript.sql)
- [`powershell/reporting/Get-IndexFragmentation.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-IndexFragmentation.ps1)

---

## SEO

**Focus keyphrase:** SQL Server index fragmentation

**Meta description** (160 chars — at limit):  
Identify fragmented SQL Server indexes across all databases and generate the right REBUILD or REORGANIZE commands. Includes thresholds, ONLINE rebuild, and when to skip it.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `index-fragmentation-output.png` | SQL Server index fragmentation query results showing fragmentation_pct, page_count, and recommended REBUILD or REORGANIZE action | SQL Server index fragmentation DMV output |
| `index-maintenance-statements.png` | Generated ALTER INDEX REBUILD and REORGANIZE statements ready to run in a maintenance window | Generated index maintenance SQL statements |
