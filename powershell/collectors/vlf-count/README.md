# VLF Count Collector

Point-in-time snapshot of Virtual Log File counts for all online user databases. High VLF counts slow log backup, recovery, and database startup. Collect daily to catch accumulating databases before they need emergency maintenance.

## Why this exists

SQL Server transaction log files are internally divided into Virtual Log Files. Each autogrowth event creates more VLFs. With small autogrowth increments or percentage-based growth, a database can accumulate thousands of VLFs over years — causing slow log backup completion times, slow database startup, and slow mirroring/AG synchronisation. This collector tracks VLF counts daily so you can spot rising trends and address them proactively (log backup + shrink cycle to reclaim VLFs).

## Output

Daily CSV at `output-files/collectors/vlf-count/`:

```text
<server>-<YYYYMMDD>.csv        one row per user database per collection run
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `database_name` | Database name |
| `recovery_model_desc` | FULL, SIMPLE, or BULK_LOGGED |
| `log_reuse_wait_desc` | Why the log cannot reuse space (LOG_BACKUP, ACTIVE_TRANSACTION, etc.) |
| `vlf_count` | Current VLF count |
| `log_file_size_mb` | Current log file size |
| `vlf_status` | OK / MONITOR (≥100) / WARNING (≥1000) / CRITICAL (≥10000) |

## Write condition

Always writes — every run appends all user databases regardless of VLF count.

## Thresholds

| Status | VLF count | Typical symptom |
|--------|-----------|-----------------|
| OK | < 100 | No concern |
| MONITOR | 100–999 | Watch over time |
| WARNING | 1,000–9,999 | Log backup slows; plan remediation |
| CRITICAL | 10,000+ | DB startup, backup, and recovery significantly impacted |

## Remediation (when VLFs are high)

```sql
-- 1. Take a log backup to free inactive VLFs
BACKUP LOG [YourDatabase] TO DISK = N'NUL';

-- 2. Shrink to reclaim space (creates fewer, larger VLFs)
USE [YourDatabase];
DBCC SHRINKFILE ([YourDatabase_log], 1);

-- 3. Pre-grow the log file to the right size with a large fixed increment
-- This creates a small number of large VLFs rather than many small ones
ALTER DATABASE [YourDatabase]
    MODIFY FILE (NAME = [YourDatabase_log], SIZE = 4096MB, FILEGROWTH = 1024MB);

-- 4. Confirm VLF count reduced
SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID('YourDatabase'));
```

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | Daily |
| Dev/test | Weekly |

## Running manually

```powershell
.\collectors\vlf-count\Collect-VlfCount.ps1
.\collectors\vlf-count\Collect-VlfCount.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - VLF Count Collector',
    @description     = N'Daily snapshot of VLF counts per database.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - VLF Count Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-tools\powershell\collectors\vlf-count\Collect-VlfCount.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name    = N'Daily 6am',
    @freq_type        = 4,
    @freq_interval    = 1,
    @freq_subday_type = 1,
    @active_start_time = 060000;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - VLF Count Collector', @schedule_name = N'Daily 6am';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - VLF Count Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`, `VIEW DATABASE STATE`