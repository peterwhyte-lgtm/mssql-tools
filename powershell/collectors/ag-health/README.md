﻿# AG Health Collector

Snapshots Availability Group replica state, synchronisation health, queue depths, and estimated failover time. Returns a single `NO_AG` row on standalone instances — always succeeds without configuration changes.

## Why this exists

AG health changes fast and the DMVs only show current state. This collector builds a timestamped history so you can answer: was the secondary already lagging before that failover test? Did redo queue depth spike during the index rebuild last night? Is estimated_data_loss_s creeping up during business hours?

## Output

Daily CSV at `output-files/collectors/ag-health/`:

```text
<server>-<YYYYMMDD>.csv        one row per AG × replica × database per collection run
<server>-collector.log
```

On standalone instances (no AG): one row with `ag_name = 'NO_AG'` and all other columns NULL. Filter these out in analysis.

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `ag_name` | Availability Group name (`NO_AG` on standalone) |
| `replica_server_name` | Server name of this replica |
| `role_desc` | `PRIMARY` or `SECONDARY` |
| `operational_state_desc` | `ONLINE`, `OFFLINE`, `RESOLVING` |
| `connected_state_desc` | `CONNECTED` or `DISCONNECTED` |
| `synchronization_health_desc` | `HEALTHY`, `PARTIALLY_HEALTHY`, `NOT_HEALTHY` |
| `last_connect_error_description` | Error if replica is disconnected |
| `database_name` | Database in the AG |
| `db_synchronization_state_desc` | `SYNCHRONIZED`, `SYNCHRONIZING`, `NOT SYNCHRONIZING` |
| `db_synchronization_health_desc` | Per-database health |
| `log_send_queue_kb` | KB of log waiting to be sent to secondary |
| `log_send_rate_kb_s` | Current send rate KB/sec |
| `redo_queue_kb` | KB of log received but not yet applied on secondary |
| `redo_rate_kb_s` | Current redo rate KB/sec |
| `last_sent_time` | Last time log was sent |
| `last_received_time` | Last time log was received by secondary |
| `last_hardened_time` | Last time log was hardened on secondary |
| `last_redone_time` | Last time log was applied on secondary |
| `estimated_redo_completion_time_s` | Seconds to clear current redo queue |
| `estimated_data_loss_s` | Seconds of data that would be lost if primary failed now |

## Key indicators

- **`redo_queue_kb` growing** — secondary is falling behind. Check `redo_rate_kb_s` vs log generation rate.
- **`estimated_data_loss_s` > 0** — the secondary is not fully caught up; a failover now would lose that many seconds of commits.
- **`synchronization_health_desc = NOT_HEALTHY`** — one or more databases are not synchronised.
- **`connected_state_desc = DISCONNECTED`** — network or service issue between replicas.

## Write condition

Always writes — every run appends rows. Filter `ag_name = 'NO_AG'` rows in analysis if monitoring mixed estates.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production AG | 1–5 minutes |
| Dev/test AG | 15 minutes |
| Standalone (no AG) | No need to run |

## Running manually

```powershell
.\collectors\ag-health\Collect-AgHealth.ps1
.\collectors\ag-health\Collect-AgHealth.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - AG Health Collector',
    @description     = N'Snapshots AG replica state and queue depths every 5 minutes.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - AG Health Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\ag-health\Collect-AgHealth.ps1"',
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

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - AG Health Collector', @schedule_name = N'Every 5 Minutes';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - AG Health Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`