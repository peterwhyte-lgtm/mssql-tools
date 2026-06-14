# Blocking Collector

Captures active blocking chains from `sys.dm_exec_requests` on a schedule. Writes to CSV **only when blocking is detected** — quiet servers produce no files.

## Why this exists

`Get-BlockingChains.sql` (in `sql/performance/`) gives you a snapshot when you notice a problem. This collector runs continuously so you have evidence of blocking that resolved before you looked, including who the head blocker was and what statement was running.

## Output

Daily CSV at `output-files/collectors/blocking/` — only written on days when blocking occurs:

```text
<server>-<YYYYMMDD>.csv        one row per blocked session per collection run
<server>-collector.log         one line per execution (including quiet runs)
```

| Column | Description |
|--------|-------------|
| `collection_time` | When the snapshot was taken |
| `server_name` | `@@SERVERNAME` |
| `blocked_spid` | Session ID of the blocked request |
| `blocking_spid` | Session ID of the blocker |
| `is_head_blocker` | 1 if this blocker is not itself blocked |
| `wait_type` | Lock wait type (e.g. `LCK_M_X`) |
| `wait_time_ms` | How long the session has been blocked |
| `wait_resource` | Which resource is locked |
| `database_name` | Database context of the blocked session |
| `login_name` | Login of the blocked session |
| `host_name` | Client hostname |
| `program_name` | Application name |
| `elapsed_ms` | Total elapsed time of the blocked request |
| `blocked_statement` | SQL text of the blocked session |
| `blocker_last_statement` | Last SQL text from the blocker (may be idle) |

## Write condition

Only writes when `blocking_session_id > 0` exists in `sys.dm_exec_requests`. Empty CSV directories mean the server has been clean for that period.

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | 1–2 minutes |
| Dev/test | 5 minutes |

At 1-minute intervals, a 10-second blocking event will appear in exactly one snapshot. At 2 minutes, a short burst may go uncaptured. Keep at 1 minute for busy OLTP systems.

## Running manually

```powershell
.\collectors\blocking\Collect-Blocking.ps1
.\collectors\blocking\Collect-Blocking.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Blocking Collector',
    @description     = N'Captures blocking chains every minute. Only writes when blocking is active.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Blocking Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\blocking\Collect-Blocking.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'Every 1 Minute',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 4,
    @freq_subday_interval = 1,
    @active_start_time    = 0,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Blocking Collector', @schedule_name = N'Every 1 Minute';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Blocking Collector';
GO
```

**Permissions required:** `VIEW SERVER STATE`

## Correlating with other collectors

| When you see this in blocking CSV... | Check... |
|--------------------------------------|----------|
| Same head blocker appearing repeatedly | `wait-stats`: is `LCK_M_X` trending up? |
| Blocking resolving as deadlocks | `deadlocks` collector for victim details |
| Long elapsed_ms on blocker with no active request | Open transaction held by an idle session |
