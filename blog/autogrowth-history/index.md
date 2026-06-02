---
title: "Script: SQL Server Autogrowth History from the Default Trace"
slug: sql-server-autogrowth-history
published: 
published_url: 
status: draft
category: monitoring
tags: [autogrowth, storage, maintenance, transaction-log, capacity]
scripts:
  - sql/monitoring/Get-AutogrowthHistory.sql
seo_keyphrase: SQL Server autogrowth history
seo_title: "SQL Server Autogrowth History — Find Undersized Files Before They're a Problem"
seo_description: Read SQL Server autogrowth events from the default trace to identify undersized files, bad growth increments, and when autogrowth happened during business hours. (164 chars — trim)
screenshots_needed:
  - Get-AutogrowthHistory output showing autogrowth events with database_name, file_name, growth_mb, duration_ms, and event_time — ideally with events during business hours visible
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Autogrowth History from the Default Trace

Autogrowth is SQL Server's safety net when a file runs out of space — not a sizing strategy. Every autogrowth event pauses the session that triggered it while SQL Server extends the file. On spinning disk this can take seconds. On a busy OLTP system with files growing in 1 MB increments (the SQL Server default), those pauses add up, and they happen during business hours when they hurt the most.

The default trace captures every autogrowth event, including which file grew, by how much, and how long the extension took. This script reads that trace history and surfaces anything worth investigating.

## The problem

Most autogrowth events go unnoticed. SQL Server extends the file, the waiting session resumes, and life goes on. There's no alert, no error message, and no log entry visible to most DBAs — just a brief pause that the application team noticed but couldn't explain.

Regular autogrowth events are a signal that files aren't sized correctly. The fix isn't faster autogrowth — it's eliminating autogrowth events by pre-sizing files to match the expected growth. Files that grow on schedule and under controlled circumstances don't generate production pauses.

## The script

```sql
SELECT
    CASE e.EventClass
        WHEN 92 THEN 'Data'
        WHEN 93 THEN 'Log'
    END                                 AS file_type,
    e.DatabaseName                      AS database_name,
    e.FileName                          AS file_name,
    e.IntegerData * 8 / 1024.0         AS growth_mb,
    e.Duration / 1000.0                AS duration_ms,
    e.StartTime                         AS event_time,
    DATENAME(weekday, e.StartTime)     AS day_of_week,
    DATEPART(hour,    e.StartTime)     AS hour_of_day
FROM sys.fn_trace_gettable(
    (SELECT path FROM sys.traces WHERE is_default = 1),
    DEFAULT
) e
WHERE e.EventClass IN (92, 93)   -- 92 = data autogrowth, 93 = log autogrowth
  AND e.StartTime > DATEADD(day, -7, GETDATE())  -- last 7 days
ORDER BY e.StartTime DESC;
```

## How to run it from the repo

```powershell
# Last 7 days of autogrowth events
.\run.ps1 Get-AutogrowthHistory

# Against a remote server
.\run.ps1 Get-AutogrowthHistory -ServerInstance MYSERVER\INST01

# Save to CSV for capacity planning
.\run.ps1 Get-AutogrowthHistory -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `file_type` | `Data` (EventClass 92) or `Log` (EventClass 93). Log autogrowths are generally more disruptive — the log must be extended before the transaction can continue. |
| `database_name` | Which database the file belongs to. |
| `file_name` | The physical file path. |
| `growth_mb` | How much the file grew in this event, in megabytes. |
| `duration_ms` | How long the extension took in milliseconds. This is the time the triggering session was paused. Values above 1000ms (1 second) are meaningful. Values above 5000ms are a problem. |
| `event_time` | When the autogrowth happened. |
| `day_of_week` / `hour_of_day` | Helps spot business-hours events. Autogrowths during working hours directly impact users. |

## What to look for

**Business-hours events** — any autogrowth between 8am and 6pm on a weekday is worth investigating. Users experienced a pause when this happened. If you see many of these, the file is consistently undersized for daily usage.

**High `duration_ms`** — extensions that take more than a second indicate either:
- Slow storage (spinning disk struggling to zero-fill a large extension)
- A large percent-based growth extending an already large file
- Instant File Initialisation not enabled for data files

**Small `growth_mb` repeated many times** — this is the 1 MB default growth increment problem. A log file growing 1 MB at a time during a big transaction will autogrow dozens or hundreds of times. Each event is a separate trace entry and a separate pause. The fix is to set a sensible fixed-size growth increment.

**Log file autogrowth more than data file** — frequent log autogrowths without corresponding data autogrowths often means transaction log sizing is wrong, or the log backup frequency is too low (log space can't be reused if log backups aren't running).

## The percent-based growth problem

SQL Server's default autogrowth settings have been bad for a long time:
- Data files: 1 MB fixed (too small)
- Log files: 10% growth (dangerous on large files)

10% growth sounds reasonable until a log file reaches 50 GB — then a single autogrowth event tries to extend the file by 5 GB. That 5 GB extension takes significant time to complete (especially without Instant File Initialisation), and it happens while a transaction is waiting.

The fix: set fixed-size growth increments appropriate to the database's growth rate. A database that grows 5 GB per month should have autogrowth set to at least 1 GB, so you have some margin between events. A database that grows 100 GB per month needs correspondingly larger increments — or better yet, pre-allocation to avoid autogrowth events entirely during the growth period.

## Instant File Initialisation

Data file extensions (EventClass 92) can be made nearly instantaneous by enabling Instant File Initialisation (IFI). With IFI enabled, SQL Server doesn't zero-fill new data file space — it just marks it as available. Log file extensions (EventClass 93) are always zeroed regardless of IFI, because the log file structure requires it.

To enable IFI: grant the SQL Server service account the "Perform volume maintenance tasks" local security right. Requires a service restart to take effect. Once enabled, data autogrowth `duration_ms` values drop to near-zero regardless of size.

Check whether IFI is currently enabled:

```sql
-- SQL Server 2012 SP4+ and SQL Server 2014 SP2+:
SELECT instant_file_initialization_enabled
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server (%';
```

## The right fix: eliminate autogrowth through pre-sizing

Autogrowth exists for emergencies — not for routine operation. A file that autogrows every week is a file that isn't sized for its workload.

The correct approach for managed databases:

1. **Determine the growth rate** — from autogrowth history, estimate monthly data growth (total `growth_mb` per database per month from data file events)

2. **Right-size the file** — allocate at least 3–6 months of projected growth upfront:

```sql
-- Grow the data file to a specified size (in MB)
USE [YourDatabase];
ALTER DATABASE [YourDatabase]
MODIFY FILE (NAME = N'YourDatabase_Data', SIZE = 51200MB);  -- 50 GB

-- Grow the log file
ALTER DATABASE [YourDatabase]
MODIFY FILE (NAME = N'YourDatabase_Log',  SIZE = 10240MB);  -- 10 GB
```

3. **Set a sensible growth increment** — so that if autogrowth does trigger (an unexpected surge, a missed review), the extension is large enough to be infrequent:

```sql
ALTER DATABASE [YourDatabase]
MODIFY FILE (NAME = N'YourDatabase_Data', FILEGROWTH = 1024MB);   -- grow by 1 GB
ALTER DATABASE [YourDatabase]
MODIFY FILE (NAME = N'YourDatabase_Log',  FILEGROWTH = 512MB);    -- grow by 512 MB
```

Fixed-size increments are always preferable to percent-based for large files.

4. **Monitor over time** — re-run `Get-AutogrowthHistory` monthly and proactively grow files when they're projected to run out within the next 2–3 months.

## The default trace limitation

The default trace is a rolling trace file — it wraps around when it reaches its size limit (typically a few hundred MB). On a very busy server with frequent events, the trace might only cover a few hours of history. On quieter servers, it can go back days or weeks.

The `WHERE StartTime > DATEADD(day, -7, ...)` clause in the script filters to the last 7 days — but if the trace has already wrapped, you'll get fewer results than that. For long-term autogrowth monitoring, consider saving the output to a table or CSV periodically.

Note: in SQL Server 2022, the default trace was deprecated in favour of Extended Events. The script includes a fallback for Extended Events-based capture if the default trace is not available.

## Related scripts

- [`Get-TransactionLogSizeAndUsage`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/inventory/Get-TransactionLogSizeAndUsage.ps1) — current log file sizes and VLF counts
- [`Get-DatabaseSizesAndFreeSpace`](../database-sizes-free-space/index.md) — current free space in each database file
- [`Get-VlfCount`](../vlf-count/index.md) — excessive autogrowth creates many VLFs, which degrade log performance

## Get the scripts

The full script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-AutogrowthHistory.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-AutogrowthHistory.sql)

---

## SEO

**Focus keyphrase:** SQL Server autogrowth history

**Meta description** (164 chars — trim to 160 before publishing):  
Read SQL Server autogrowth events from the default trace to identify undersized files, bad growth increments, and when autogrowth happened during business hours.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `autogrowth-history-output.png` | Get-AutogrowthHistory output showing log file autogrowth events during business hours with duration_ms over 2000 | Autogrowth events during business hours |
