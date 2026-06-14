﻿# Deadlock Collector

Extracts deadlock events from the `system_health` XEvent ring buffer and appends **new events only** to the daily CSV. No XEvent session configuration required — `system_health` is always running.

## Why this exists

The `system_health` ring buffer holds ~250 events and rolls over. Without collection, deadlocks that happened at 3am are gone by morning. This collector runs on a short interval and filters to events newer than the last captured timestamp, so duplicates never appear even on back-to-back runs.

## Output

Daily CSV at `output-files/collectors/deadlocks/` — only written when new deadlocks are detected:

```text
<server>-<YYYYMMDD>.csv        one row per deadlock event
<server>-collector.log         one line per execution
```

| Column | Description |
|--------|-------------|
| `collection_time` | When this row was captured |
| `server_name` | `@@SERVERNAME` |
| `deadlock_time` | When the deadlock occurred (from XEvent timestamp) |
| `victim_process_id` | Internal process ID of the chosen victim |
| `victim_spid` | Session ID of the deadlock victim |
| `victim_login` | Login of the victim session |
| `victim_statement` | SQL statement the victim was running |
| `process_count` | Number of processes involved in the deadlock |
| `deadlock_xml` | Full deadlock graph XML for detailed investigation |

## Write condition

Only writes when new deadlock events exist in the ring buffer that are newer than the most recently captured event. The collector tracks `deadlock_time` to determine novelty.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | 1–5 minutes |
| Dev/test | 5–15 minutes |

The ring buffer holds ~250 events. On very busy systems generating many deadlocks per minute, run at 1 minute. Otherwise 5 minutes is fine — the filter prevents duplicates regardless.

## Running manually

```powershell
.\collectors\deadlocks\Collect-Deadlocks.ps1
.\collectors\deadlocks\Collect-Deadlocks.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Deadlock Collector',
    @description     = N'Extracts new deadlock events from system_health ring buffer.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Deadlock Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\deadlocks\Collect-Deadlocks.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'Every 5 Minutes',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 4,
    @freq_subday_interval = 5,
    @active_start_time    = 0,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Deadlock Collector', @schedule_name = N'Every 5 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Deadlock Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`

## Investigating deadlock_xml

The raw XML in `deadlock_xml` can be pasted into SSMS → File → Open → XML, or opened with any XML viewer. It contains the full deadlock graph: both processes, their lock lists, and the statements involved. The victim was chosen by SQL Server based on deadlock priority and rollback cost.