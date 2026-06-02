---
title: "Script: SQL Server Database Sizes and Free Space Across All Databases"
slug: sql-server-database-sizes-free-space
published: 
published_url: 
status: draft
category: monitoring
tags: [storage, capacity, monitoring, disk-space, databases]
scripts:
  - sql/monitoring/Get-DatabaseSizesAndFreeSpace.sql
  - sql/monitoring/Get-Databases.sql
seo_keyphrase: SQL Server database sizes free space
seo_title: "SQL Server Database Sizes and Free Space — Accurate Across All Databases"
seo_description: Query SQL Server data and log file sizes with accurate free space across all databases. Uses database-scoped FILEPROPERTY to avoid the common NULL result bug. (159 chars)
screenshots_needed:
  - Get-DatabaseSizesAndFreeSpace output showing database_name, file_type, size_mb, free_space_mb, and pct_free per file across all databases
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Database Sizes and Free Space Across All Databases

Knowing how much space your databases are using — and how much is left — sounds simple. In practice, getting accurate free space numbers in SQL Server requires querying in the right database context. A common mistake is querying `sys.master_files` with `FILEPROPERTY` from master, which returns NULL for every database except master itself. The result is a report that looks complete but has missing data for everything important.

This script uses dynamic SQL to execute in the context of each database, producing accurate free space numbers for every data and log file on the instance.

## The FILEPROPERTY-from-master problem

`FILEPROPERTY` is a database-scoped function. It operates on files in the *current database context*. When you call it from master:

```sql
-- This looks right but returns NULL for most databases
SELECT
    name,
    size * 8 / 1024.0           AS size_mb,
    FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024.0  AS used_mb  -- NULL for non-master databases
FROM sys.master_files
WHERE database_id > 4;
```

`FILEPROPERTY(name, 'SpaceUsed')` returns the space used for a file in the *current database* by that name. From master, it can only see master's files. Any `name` that doesn't match a master file returns NULL.

The correct approach: execute `FILEPROPERTY` inside each database's context using dynamic SQL. That's what this script does.

## The scripts

### Get-DatabaseSizesAndFreeSpace.sql — accurate free space per file

```sql
CREATE TABLE #file_space (
    database_name   SYSNAME,
    file_id         INT,
    file_name       SYSNAME,
    file_type       NVARCHAR(60),
    physical_name   NVARCHAR(260),
    size_mb         DECIMAL(12,2),
    used_mb         DECIMAL(12,2),
    free_mb         DECIMAL(12,2),
    pct_free        DECIMAL(5,1)
);

DECLARE @sql NVARCHAR(MAX);

SELECT @sql = STRING_AGG(
    N'INSERT INTO #file_space
    SELECT
        DB_NAME(' + CAST(database_id AS NVARCHAR(10)) + N') AS database_name,
        file_id,
        name,
        type_desc,
        physical_name,
        CAST(size * 8.0 / 1024 AS DECIMAL(12,2))                                    AS size_mb,
        CAST(FILEPROPERTY(name, ''SpaceUsed'') * 8.0 / 1024 AS DECIMAL(12,2))       AS used_mb,
        CAST((size - FILEPROPERTY(name, ''SpaceUsed'')) * 8.0 / 1024 AS DECIMAL(12,2)) AS free_mb,
        CAST(100.0 * (size - FILEPROPERTY(name, ''SpaceUsed'')) / NULLIF(size,0) AS DECIMAL(5,1)) AS pct_free
    FROM ' + QUOTENAME(name) + N'.sys.database_files;',
    CHAR(13) + CHAR(10)
)
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4;   -- skip system databases; adjust as needed

EXEC sp_executesql @sql;

SELECT *
FROM #file_space
ORDER BY database_name, file_type, file_name;

DROP TABLE #file_space;
```

### Get-Databases.sql — high-level properties overview

```sql
SELECT
    d.name                              AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    d.compatibility_level,
    d.collation_name,
    d.is_read_only,
    d.is_auto_shrink_on,
    d.is_auto_close_on,
    d.page_verify_option_desc,
    d.log_reuse_wait_desc,
    d.create_date,
    SUM(CASE mf.type WHEN 0 THEN mf.size ELSE 0 END) * 8 / 1024.0  AS data_size_mb,
    SUM(CASE mf.type WHEN 1 THEN mf.size ELSE 0 END) * 8 / 1024.0  AS log_size_mb
FROM sys.databases d
JOIN sys.master_files mf ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level,
         d.collation_name, d.is_read_only, d.is_auto_shrink_on, d.is_auto_close_on,
         d.page_verify_option_desc, d.log_reuse_wait_desc, d.create_date
ORDER BY data_size_mb DESC;
```

## How to run it from the repo

```powershell
# Sizes and free space for all databases
.\run.ps1 Get-DatabaseSizesAndFreeSpace

# High-level database properties overview
.\run.ps1 Get-Databases

# Save both to CSV for capacity planning
.\run.ps1 Get-DatabaseSizesAndFreeSpace -OutputFormat Csv
.\run.ps1 Get-Databases -OutputFormat Csv
```

## Reading the output — Get-DatabaseSizesAndFreeSpace

| Column | What it means |
|--------|---------------|
| `database_name` | Database name. |
| `file_type` | `ROWS` for data files, `LOG` for log files. |
| `file_name` | Logical file name. |
| `physical_name` | Full path to the physical file on disk. Helps identify which drive it's on. |
| `size_mb` | Total allocated file size. This is what the file currently occupies on disk — it includes both used and free space inside the file. |
| `used_mb` | Space actually consumed by data or log records within the file. |
| `free_mb` | Unallocated space inside the file. SQL Server can use this for new data without extending the file on disk. |
| `pct_free` | Free space as a percentage of total file size. The most useful column for capacity planning. |

## What to look for

**Low `pct_free` on data files** — below 10–15% means the file will need to grow soon. Below 5% means it needs attention immediately.

**Low `pct_free` on log files** — log free space also depends on log backup frequency. A log file with 5% free space that has a log backup running every 15 minutes may be fine — the backed-up space is reclaimed. A log file with 5% free and `log_reuse_wait_desc = LOG_BACKUP` (visible in `Get-Databases`) means log backups aren't running and the log can't reuse space.

**Very high `pct_free` on a data file** — a file that's 70% free was probably allocated large but the data hasn't grown into it. This is fine if the allocation was intentional (pre-sized). It becomes a concern only if the disk is under pressure and you're wondering whether to reclaim space (see the shrink discussion below).

**`physical_name` pointing to unexpected drives** — databases on C: drives, or log files sharing a drive with data files. Both are common configuration problems to flag.

## Reading the output — Get-Databases

The `Get-Databases` script surfaces database-level properties that are quick to scan for problems:

**`is_auto_shrink_on = 1`** — auto shrink is enabled. This is almost always bad. Auto shrink periodically reclaims unused space, then SQL Server autogrows when data grows again. The shrink/grow cycle fragments files, wastes I/O on useless work, and produces autogrowth events during business hours. Disable it on any database where it's on:

```sql
ALTER DATABASE [YourDatabase] SET AUTO_SHRINK OFF;
```

**`log_reuse_wait_desc`** — what's preventing the transaction log from reusing space:
- `LOG_BACKUP` — log backups aren't running or haven't run recently. Log will keep growing.
- `ACTIVE_TRANSACTION` — a long-running transaction is holding log space open.
- `DATABASE_MIRRORING` / `AVAILABILITY_REPLICA` — the AG secondary or mirror is behind.
- `NOTHING` — normal; log space is being reused freely.

**`recovery_model_desc = SIMPLE` with `LOG_BACKUP` log_reuse_wait** — impossible combination; Simple recovery mode doesn't support log backups and log space is automatically reclaimed at checkpoints. If you're seeing log growth in Simple recovery, look for long-running transactions.

**`compatibility_level` below 150 (SQL Server 2019) or 160 (SQL Server 2022)** — older compat levels miss out on query optimiser improvements, dynamic statistics threshold, and other features. Worth noting for the backlog.

## Note on shrinking databases

High `pct_free` tempts DBAs to shrink files. In almost all cases, don't. Shrinking a data file causes severe index fragmentation — the data pages get compacted but in a random order, fragmenting every index. The space saving is temporary because data will grow back, requiring autogrowth. The fragmentation is permanent until you run index maintenance.

The only legitimate case for shrinking data files is when a large permanent data deletion (archiving, purging) leaves the file significantly oversized and you need to reclaim disk space. Even then, rebuild indexes after shrinking.

Log files can be safely shrunk with `DBCC SHRINKFILE` after confirming log backups are running and VLF count is not excessive.

## Related scripts

- [`Get-AutogrowthHistory`](../autogrowth-history/index.md) — see when files have been autograowing and by how much
- [`Get-VlfCount`](../vlf-count/index.md) — excessive log autogrowth creates VLF fragmentation
- [`Get-DiskSpace`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/inventory/Get-DiskSpace.ps1) — available space on the drives hosting the database files

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-DatabaseSizesAndFreeSpace.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-DatabaseSizesAndFreeSpace.sql)
- [`sql/monitoring/Get-Databases.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-Databases.sql)

---

## SEO

**Focus keyphrase:** SQL Server database sizes free space

**Meta description** (159 chars — target 150–160):  
Query SQL Server data and log file sizes with accurate free space across all databases. Uses database-scoped FILEPROPERTY to avoid the common NULL result bug.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `database-sizes-output.png` | Get-DatabaseSizesAndFreeSpace output showing size_mb, used_mb, free_mb, and pct_free per file for multiple databases | Database file sizes and free space |
| `get-databases-output.png` | Get-Databases output showing recovery_model_desc, log_reuse_wait_desc, and is_auto_shrink_on columns for each database | Database properties overview |
