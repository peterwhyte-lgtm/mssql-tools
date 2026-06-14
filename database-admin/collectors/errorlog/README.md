# Errorlog Collector

Reads new entries from the SQL Server error log and appends only novel entries (by timestamp) to the daily CSV. Builds a searchable history of SQL Server errors over time without duplicating entries on back-to-back runs.

## Why this exists

The SQL Server error log cycles and overwrites. Without collection, errors from last Tuesday's incident may be gone. This collector runs on a short interval and deduplicates by `log_date`, so you accumulate a full day's error log events in one CSV — searchable, filterable, and correlatable with wait-stats or blocking events at the same timestamp.

## Output

Daily CSV at `output-files/collectors/errorlog/`:

```text
<server>-<YYYYMMDD>.csv        new error/warning entries since last run
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | When this row was captured by the collector |
| `server_name` | `@@SERVERNAME` |
| `log_date` | Timestamp of the error log entry |
| `process_info` | Process that logged the entry (e.g. `spid12s`, `Backup`) |
| `severity` | Classified as `Error`, `Warning`, or `Info` |
| `message_text` | Log entry text (first 2000 characters) |

## Write condition

Only writes when new entries are found that are newer than the most recently captured `log_date`. Quiet periods produce no new CSV rows. Successful logins, BACKUP DATABASE messages, and log backup messages are suppressed as noise.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | 5–15 minutes |
| Dev/test | 30–60 minutes |

## Running manually

```powershell
.\collectors\errorlog\Collect-Errorlog.ps1
.\collectors\errorlog\Collect-Errorlog.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Errorlog Collector',
    @description     = N'Reads new SQL Server error log entries every 15 minutes.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Errorlog Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\errorlog\Collect-Errorlog.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'Every 15 Minutes',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 4,
    @freq_subday_interval = 15,
    @active_start_time    = 0,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Errorlog Collector', @schedule_name = N'Every 15 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Errorlog Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`; `EXECUTE` on `sys.xp_readerrorlog` (granted by default to `sysadmin` and `securityadmin`)
