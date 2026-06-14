﻿# TempDB Collector

Snapshots TempDB file-level space usage and the top session consumers. Point-in-time — no delta calculation needed.

## Why this exists

TempDB pressure is one of the harder problems to diagnose after the fact. This collector captures a picture of how full TempDB is, what type of space is consumed (user objects, internal objects, version store), and which sessions are the heaviest consumers — all timestamped so you can correlate with a `PAGELATCH_EX` spike in wait-stats or a user-reported slowdown.

## Output

Daily CSV at `output-files/collectors/tempdb/`:

```text
<server>-<YYYYMMDD>.csv        mixed file-level and session-level rows
<server>-collector.log
```

Each snapshot produces two row types, identified by the `row_type` column:

### row_type = 'file' (one row per TempDB data/log file)

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `row_type` | `'file'` |
| `file_name` | TempDB logical file name |
| `physical_name` | Full path to the file |
| `file_type` | `ROWS` or `LOG` |
| `file_size_mb` | Total allocated file size |
| `total_allocated_mb` | Pages allocated inside the file |
| `free_mb` | Unallocated extents (available space) |
| `user_objects_mb` | Space used by temp tables and table variables |
| `internal_objects_mb` | Space used by SQL Server internals (sort spills, hash joins) |
| `version_store_mb` | Space used by the version store (row versioning, snapshot isolation) |
| `mixed_extents_mb` | Mixed extent pages (pre-allocation overhead) |

### row_type = 'session' (top 10 consumers, NULLs for file columns)

| Column | Description |
|--------|-------------|
| `session_id` | Session using TempDB space |
| `login_name` | Login of the session |
| `host_name` | Client hostname |
| `program_name` | Application name |
| `session_user_objects_mb` | Temp tables / table variables allocated by this session |
| `session_internal_objects_mb` | Internal sort/hash spill space allocated by this session |

## Write condition

Always writes — every run appends regardless of TempDB usage level.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production (high TempDB usage) | 5 minutes |
| Production (normal) | 15 minutes |
| Dev/test | 30 minutes |

## Running manually

```powershell
.\collectors\tempdb\Collect-TempDb.ps1
.\collectors\tempdb\Collect-TempDb.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - TempDB Collector',
    @description     = N'Snapshots TempDB file space and top consumers every 15 minutes.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - TempDB Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\tempdb\Collect-TempDb.ps1"',
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

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - TempDB Collector', @schedule_name = N'Every 15 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - TempDB Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`, `VIEW DATABASE STATE`

## Diagnosing version store pressure

If `version_store_mb` is large and growing:
- A long-running transaction is holding the version store open
- Check `sys.dm_tran_active_transactions` for old transactions
- Compare with `blocking` collector for open transactions holding locks