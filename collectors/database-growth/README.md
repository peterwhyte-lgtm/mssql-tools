# Database Growth Collector

Point-in-time snapshot of every database file's size, autogrowth settings, space to growth limit, and a growth risk flag. No delta calculation needed — each snapshot is standalone.

## Why this exists

Database files grow silently until they hit a limit or fill the disk. This collector builds a daily record of file sizes so you can answer: how fast is the Orders database growing per week? Which files have a growth limit less than 1 GB away? Which files are using percentage-based autogrowth (often a problem)?

## Output

Daily CSV at `output-files/collectors/database-growth/`:

```text
<server>-<YYYYMMDD>.csv        one row per database file per collection run
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `database_name` | Database name |
| `database_state` | `ONLINE`, `OFFLINE`, `RESTORING`, etc. |
| `recovery_model_desc` | `FULL`, `SIMPLE`, `BULK_LOGGED` |
| `logical_name` | Logical file name |
| `physical_name` | Full path to the file |
| `file_type` | `ROWS` (data) or `LOG` |
| `file_size_mb` | Current allocated file size |
| `space_to_limit_mb` | MB remaining before the file hits its configured max size (NULL = unlimited) |
| `autogrowth` | Autogrowth setting, e.g. `256 MB` or `10%` |
| `is_percent_growth` | 1 if autogrowth is percentage-based |
| `growth_limit_mb` | Configured maximum file size (NULL = unlimited) |
| `growth_status` | `OK`, `NEAR_LIMIT` (< 1 GB to limit), `AT_LIMIT`, `UNLIMITED` |

## Write condition

Always writes — every run appends one row per file for all ONLINE databases.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | Every 1–6 hours |
| Dev/test | Daily |

Hourly collection is usually sufficient — file growth events are visible at this granularity. Daily collection is enough for trend analysis but misses the exact time of an autogrowth event.

## Running manually

```powershell
.\collectors\database-growth\Collect-DatabaseGrowth.ps1
.\collectors\database-growth\Collect-DatabaseGrowth.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Database Growth Collector',
    @description     = N'Snapshots database file sizes and autogrowth settings hourly.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Database Growth Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-scripts\collectors\database-growth\Collect-DatabaseGrowth.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'Hourly',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 8,
    @freq_subday_interval = 1,
    @active_start_time    = 0,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Database Growth Collector', @schedule_name = N'Hourly';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Database Growth Collector';
GO
```

**Permissions required:** `VIEW ANY DATABASE`, `VIEW DATABASE STATE`

## growth_status reference

| Status | Meaning |
|--------|---------|
| `OK` | File has a limit set and more than 1 GB of headroom |
| `NEAR_LIMIT` | File has a limit set and less than 1 GB remaining — review now |
| `AT_LIMIT` | File has reached its configured maximum — will fail to grow |
| `UNLIMITED` | No growth limit set (max_size = -1 or 2 TB physical cap) |
