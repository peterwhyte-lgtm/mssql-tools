﻿# Storage I/O Collector

Snapshots cumulative I/O statistics per database file from `sys.dm_io_virtual_file_stats`. Diff adjacent snapshots to measure read/write throughput and latency within each collection interval. Same delta model as wait-stats.

## Why this exists

SQL Server's I/O stats are cumulative since restart. A point-in-time query shows totals you can't interpret without a baseline. This collector builds the baseline so you can answer: which database file was generating the most I/O during last night's batch job? Is data file read latency worsening over time? Which log file is busiest?

## Output

Daily CSV at `output-files/collectors/storage-io/`:

```text
<server>-<YYYYMMDD>.csv        one row per database file per collection run
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `sqlserver_start_time` | SQL Server start time — use for restart detection |
| `database_name` | Database name |
| `physical_name` | Full path to the file |
| `file_type` | `ROWS` (data) or `LOG` |
| `database_id` | Internal database ID |
| `file_id` | Internal file ID |
| `num_of_reads` | Cumulative read operations since start |
| `num_of_bytes_read` | Cumulative bytes read since start |
| `io_stall_read_ms` | Cumulative read stall time since start |
| `num_of_writes` | Cumulative write operations since start |
| `num_of_bytes_written` | Cumulative bytes written since start |
| `io_stall_write_ms` | Cumulative write stall time since start |
| `io_stall` | Cumulative total stall (read + write) |
| `avg_read_latency_ms` | Point-in-time average read latency (derived — best diffed between snapshots) |
| `avg_write_latency_ms` | Point-in-time average write latency (derived) |
| `file_size_mb` | Current file size |

## Delta calculation

Like wait-stats, the I/O counters are cumulative. To get I/O activity for a specific interval:

```text
interval_reads        = snapshot2.num_of_reads        - snapshot1.num_of_reads
interval_bytes_read   = snapshot2.num_of_bytes_read   - snapshot1.num_of_bytes_read
interval_read_stall   = snapshot2.io_stall_read_ms    - snapshot1.io_stall_read_ms

avg_read_latency_ms   = interval_read_stall / interval_reads   (when interval_reads > 0)
```

**Restart detection:** if `snapshot2.sqlserver_start_time != snapshot1.sqlserver_start_time`, discard that delta — counters reset on restart.

## Write condition

Always writes — every run appends one row per file.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | 15–30 minutes |
| Dev/test | 30–60 minutes |

A 30-minute interval on a mid-size instance produces 20–50 rows per snapshot (one per file), or roughly 1,000–2,500 rows per day. Daily CSV stays under 500 KB.

## Running manually

```powershell
.\collectors\storage-io\Collect-StorageIo.ps1
.\collectors\storage-io\Collect-StorageIo.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Storage I/O Collector',
    @description     = N'Snapshots file-level I/O stats every 30 minutes for latency trend analysis.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Storage I/O Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\storage-io\Collect-StorageIo.ps1"',
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

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Storage I/O Collector', @schedule_name = N'Every 30 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Storage I/O Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`, `VIEW DATABASE STATE`