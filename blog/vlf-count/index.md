---
title: "Script: SQL Server VLF Count — The Hidden Log Performance Problem"
slug: sql-server-vlf-count
published: 
published_url: 
status: draft
category: performance
tags: [transaction-log, vlf, performance, maintenance, recovery]
scripts:
  - sql/monitoring/Get-VlfCount.sql
  - sql/monitoring/Get-TransactionLogSizeAndUsage.sql
seo_keyphrase:    SQL Server VLF count
seo_title:        "Script: SQL Server VLF Count — The Hidden Log Performance Problem"
seo_description:  High VLF counts silently degrade SQL Server log backup, recovery, and AG synchronisation performance. Here's how to find them and fix them in minutes. (160 chars)
screenshots_needed:
  - Get-VlfCount output showing databases sorted by vlf_count descending — highlight a database with 500+ VLFs
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server VLF Count — The Hidden Log Performance Problem

VLF count is one of those checks that doesn't appear in most performance reviews, doesn't generate an alert, and doesn't slow down any single query you can point to. It just makes everything involving the transaction log slower than it should be: backups, restores, recovery after a crash, AG synchronisation lag. I've seen databases with 15,000 VLFs that were "fine" right up until a 3-hour restore window during a failover.

It takes about two minutes to fix on any database. The script to check it takes seconds.

## The problem

Every SQL Server transaction log is divided into sections called Virtual Log Files (VLFs). SQL Server uses VLFs to manage which parts of the log are active, which can be overwritten, and where recovery needs to start from. A few hundred VLFs is normal. Tens of thousands is a performance hazard.

High VLF counts accumulate silently, almost always from the same cause: a transaction log that started small and grew through many small autogrowth events. Each autogrowth event creates new VLFs. If the log grew in 64MB increments a thousand times over years of operation, you now have thousands of VLFs.

**What actually gets slower with high VLF counts:**

- **Log backup time** — SQL Server must scan VLF headers during backup. More VLFs = longer scan.
- **Recovery time after a crash** — The redo and undo phases must traverse VLF boundaries. 10,000 VLFs means 10,000 header reads just to start.
- **AG synchronisation** — Secondary replicas must process the log in VLF units. A high-VLF log in a high-throughput AG will show measurable redo latency.
- **Log restore chains** — Restoring a sequence of log backups, each internally fragmented, compounds the issue.

## The script

```sql
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM sys.system_objects WHERE name = 'dm_db_log_info' AND type = 'IF')
BEGIN
    -- SQL Server 2016 SP2+ / 2017 CU4+
    SELECT
        d.name                                          AS database_name,
        COUNT(*)                                        AS vlf_count,
        CAST(SUM(li.vlf_size_mb) AS DECIMAL(10,2))     AS log_size_mb,
        CASE
            WHEN COUNT(*) > 1000 THEN 'CRITICAL'
            WHEN COUNT(*) > 200  THEN 'HIGH'
            WHEN COUNT(*) > 50   THEN 'ELEVATED'
            ELSE 'OK'
        END                                             AS status
    FROM sys.databases d
    CROSS APPLY sys.dm_db_log_info(d.database_id) li
    WHERE d.state_desc  = 'ONLINE'
      AND d.database_id > 4
    GROUP BY d.name, d.database_id
    ORDER BY vlf_count DESC;
END
ELSE
BEGIN
    -- SQL Server 2012 – 2016 SP1 fallback using DBCC LOGINFO
    -- (see repo for full cursor-based version)
    PRINT 'Run the repo script for a version-compatible implementation.';
END
```

> The full version of this script in the repo handles both code paths automatically and works from SQL Server 2012 onwards. The `sys.dm_db_log_info` path (2016 SP2+) is a single query with no dynamic SQL; the fallback iterates each database via a cursor.

## How to run from the repo

```powershell
# Check VLF counts across all user databases
.\run.ps1 Get-VlfCount

# Save to CSV for review or baselining
.\run.ps1 Get-VlfCount -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `database_name` | The database being assessed |
| `vlf_count` | Total number of VLFs in the transaction log |
| `log_size_mb` | Total log file size — useful context for whether the count is expected |
| `status` | `OK` (<50), `ELEVATED` (50–200), `HIGH` (200–1000), `CRITICAL` (>1000) |

There's no universal "safe" threshold. A 200GB log might legitimately have more VLFs than a 2GB log. The concern is when the count is disproportionately high for the file size — particularly anything above 1,000, which is almost always from years of uncontrolled autogrowth.

## What to look for

**`status = CRITICAL` on any database** — Fix this before the next time that database needs recovery. 1,000+ VLFs is a real operational risk during a failover.

**A large log file with a high VLF count** — A 50GB log shouldn't have 8,000 VLFs. It grew in tiny increments. The fix is the same as for a small log: shrink then grow once.

**A small log file with a very high VLF count** — Worse in a way: the log is very active and has outgrown then been shrunk repeatedly, each cycle creating more VLFs. Check `Get-TransactionLogSizeAndUsage.sql` to understand whether the log is actually being sized correctly.

**A database in an Availability Group with elevated VLF count** — This will show up as redo queue lag on the secondary. The secondary must process each VLF in order. Fix the primary and the secondary catches up.

## How to fix it

The fix is: shrink the log, then grow it in one large step to its expected working size.

```sql
-- Step 1: check current log usage before shrinking
-- (only shrink the FREE space — don't shrink below what's actually in use)
SELECT
    name,
    log_size_mb     = size * 8.0 / 1024,
    log_used_mb     = FILEPROPERTY(name, 'SpaceUsed') * 8.0 / 1024
FROM sys.database_files
WHERE type_desc = 'LOG';

-- Step 2: shrink the log file (substitute your database and log file name)
USE [YourDatabase];
DBCC SHRINKFILE (YourDatabase_log, 1);   -- shrink to 1MB minimum

-- Step 3: grow it in one large increment (e.g. 10GB for a busy database)
ALTER DATABASE [YourDatabase]
    MODIFY FILE (NAME = YourDatabase_log, SIZE = 10240MB);

-- Step 4: set a sensible fixed growth increment (not percent-based)
ALTER DATABASE [YourDatabase]
    MODIFY FILE (NAME = YourDatabase_log, FILEGROWTH = 1024MB);
```

After this, check the VLF count again. A 10GB log grown in one step will have a handful of VLFs (typically 8–16 depending on size). A log grown in 1MB steps would have had thousands.

**Right-sizing the log:** Run `Get-TransactionLogSizeAndUsage.sql` first. Look at the peak log usage percentage during a normal business period. Size the log to that peak usage plus a safety margin (typically 20–30%). Set a fixed growth increment (e.g. 1GB) as a fallback, not as the primary sizing mechanism.

## Gotchas

- **Don't shrink a log that's actively in use.** Check log space used before shrinking. Shrinking a log that's 80% active will fail to reclaim space and leave you with the same fragmentation.
- **DBCC SHRINKFILE doesn't always shrink to the target immediately.** If there are active transactions or the log is in FULL recovery with a pending backup, the virtual log at the end can't be freed until after the next log backup.
- **You cannot shrink a log that has no recent log backup (FULL recovery model).** Take a log backup first to truncate the log, then shrink.
- **SIMPLE recovery model databases:** The log truncates automatically at each checkpoint. Shrink and resize is straightforward.
- **After the fix, monitor autogrowth events.** If the log grows again quickly in small increments, the sizing is still wrong. Use `Get-AutogrowthHistory.sql` to track growth events over time.

## Related scripts in this repo

- [`Get-TransactionLogSizeAndUsage.sql`](../sql/monitoring/Get-TransactionLogSizeAndUsage.sql) — actual log space used vs allocated; use this to right-size before fixing VLFs
- [`Get-AutogrowthHistory.sql`](../sql/monitoring/Get-AutogrowthHistory.sql) — see how often and how much the log has been growing; diagnoses the root cause
- [`Get-DatabaseSizesAndFreeSpace.sql`](../sql/monitoring/Get-DatabaseSizesAndFreeSpace.sql) — broader database sizing context

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-VlfCount.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-VlfCount.sql)
- [`sql/monitoring/Get-TransactionLogSizeAndUsage.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-TransactionLogSizeAndUsage.sql)

---

## SEO

**Focus keyphrase:** SQL Server VLF count

**Meta description** (160 chars):  
High VLF counts silently degrade SQL Server log backup, recovery, and AG synchronisation performance. Here's how to find them and fix them in minutes.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `vlf-count-output.png` | SQL Server VLF count query results showing database names, VLF counts, and status ratings from OK to CRITICAL | SQL Server VLF count query output |
| `vlf-fix-steps.png` | SSMS showing DBCC SHRINKFILE followed by ALTER DATABASE MODIFY FILE to reset VLF count | SQL Server log VLF fix commands |
