# Query Store Collector

Captures the top 50 queries by average CPU time from the most recently completed runtime stats interval, for every database with Query Store enabled. Build a timestamped history to detect plan regressions and query performance trends over time.

## Why this exists

Query Store's built-in retention is limited and its UI is per-database. This collector extracts the top queries at a regular interval and writes them to a CSV — you can then trend CPU over days/weeks, spot regressions after deployments, and correlate query behaviour with wait-stats spikes at the same timestamp.

## Output

Daily CSV at `output-files/collectors/query-store/`:

```text
<server>-<YYYYMMDD>.csv        top 50 queries per DB per completed QS interval
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | When this row was captured |
| `server_name` | `@@SERVERNAME` |
| `database_name` | Database where Query Store is enabled |
| `query_id` | Query Store internal query ID |
| `query_sql_text` | SQL text (first 500 characters) |
| `plan_id` | Execution plan ID |
| `query_plan_hash` | Hash of the query plan |
| `interval_start` | Start of the runtime stats interval |
| `interval_end` | End of the interval |
| `count_executions` | Executions in this interval |
| `avg_cpu_ms` | Average CPU time per execution (ms) |
| `avg_duration_ms` | Average total duration per execution (ms) |
| `avg_logical_io_reads` | Average logical reads per execution |
| `avg_rowcount` | Average rows returned per execution |
| `is_forced_plan` | 1 if this plan is forced via sp_query_store_force_plan |
| `plan_forcing_type_desc` | How the plan was forced (MANUAL, AUTO, etc.) |

## Write condition

Only writes intervals not already captured (deduplicates on `database_name` + `interval_start`). Back-to-back runs do not produce duplicate rows. If Query Store is not enabled in a database, that database is skipped silently.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | 15–30 minutes (match the QS interval setting) |
| Dev/test | 60 minutes |

The Query Store runtime stats interval (default 60 minutes in SQL 2016, 15 minutes in SQL 2022) controls how granular the data is. Collecting more frequently than the QS interval captures the same data multiple times.

## Running manually

```powershell
.\collectors\query-store\Collect-QueryStore.ps1
.\collectors\query-store\Collect-QueryStore.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Query Store Collector',
    @description     = N'Captures top QS queries from all enabled databases every 30 minutes.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Query Store Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-scripts\collectors\query-store\Collect-QueryStore.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'Every 30 Minutes',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 4,
    @freq_subday_interval = 30,
    @active_start_time    = 0,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Query Store Collector', @schedule_name = N'Every 30 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Query Store Collector';
GO
```

**Permissions required:** `VIEW DATABASE STATE` on each database with Query Store enabled.

## Enabling Query Store

```sql
-- Enable on a user database (SQL 2016+)
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON;
ALTER DATABASE [YourDatabase] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    MAX_STORAGE_SIZE_MB = 500
);
```
