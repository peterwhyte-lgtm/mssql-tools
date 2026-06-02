# Perfmon Collector

Snapshots SQL Server performance counters from `sys.dm_os_performance_counters`. Covers buffer pool, memory, throughput, connections, locks, and I/O. Some counters are cumulative (require delta) — the `cntr_type` column identifies which.

## Why this exists

`sys.dm_os_performance_counters` gives you the same data as Windows Performance Monitor but accessible via SQL, with no perfmon configuration needed. This collector captures the counters that matter most for SQL Server health so you can correlate memory pressure, compile rate spikes, and I/O counts with wait-stats snapshots.

## Output

Daily CSV at `output-files/collectors/perfmon/`:

```text
<server>-<YYYYMMDD>.csv        one row per counter per collection run
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `object_name` | Counter object (e.g. `SQLServer:Buffer Manager`) |
| `counter_name` | Counter name (e.g. `Page life expectancy`) |
| `instance_name` | Instance qualifier (e.g. `_Total`, database name, or blank) |
| `cntr_value` | Raw counter value |
| `cntr_type` | How to interpret cntr_value — see below |

### Counter types (`cntr_type`)

| cntr_type | Type | How to use |
|-----------|------|------------|
| 65792 | Point-in-time gauge | Use directly — e.g. `Page life expectancy`, `User Connections` |
| 272696576 | Cumulative counter | Diff adjacent snapshots — e.g. `Batch Requests/sec`, `Page reads/sec` |
| 537003264 | Ratio numerator | Divide by the matching base row — e.g. `Buffer cache hit ratio` |
| 1073939712 | Ratio base (denominator) | Paired with 537003264 rows |

### Counters captured

- **Buffer Manager:** PLE, cache hit ratio, checkpoint pages/sec, lazy writes/sec, page reads/writes
- **Memory Manager:** grants outstanding/pending, target/total/stolen memory KB
- **SQL Statistics:** batch requests/sec, compilations/sec, recompilations/sec
- **General Statistics:** user connections, active temp tables, temp table creation rate
- **Locks (_Total):** lock waits/sec, lock wait time, deadlocks/sec
- **Databases (_Total):** transactions/sec, log flushes/sec, log bytes flushed
- **Access Methods:** table lock escalations, worktable creation
- **Plan Cache (_Total):** cache hit ratio, object counts, cache pages

## Write condition

Always writes — every run appends all matching counter rows.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | 1–5 minutes |
| Dev/test | 15 minutes |

## Running manually

```powershell
.\collectors\perfmon\Collect-Perfmon.ps1
.\collectors\perfmon\Collect-Perfmon.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Perfmon Collector',
    @description     = N'Snapshots SQL Server performance counters every 5 minutes.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Perfmon Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-scripts\collectors\perfmon\Collect-Perfmon.ps1"',
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

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Perfmon Collector', @schedule_name = N'Every 5 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Perfmon Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`

## Correlating with wait-stats

| Perfmon signal | Wait-stats correlation |
|----------------|----------------------|
| PLE dropping | `PAGEIOLATCH_*` — reads going to disk |
| Memory grants pending > 0 | `RESOURCE_SEMAPHORE` waits |
| High recompilations/sec | `SOS_SCHEDULER_YIELD` or plan cache pressure |
| Deadlocks/sec rising | `LCK_M_*` in wait-stats + deadlocks collector |
