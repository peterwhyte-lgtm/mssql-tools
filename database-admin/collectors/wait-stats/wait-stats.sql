/*
Script Name : wait-stats
Category    : collectors
Purpose     : Raw wait stats snapshot for historical trend analysis. Captures all
              actionable wait types with cumulative counters. Run on a schedule;
              diff adjacent snapshots to measure waits within each collection interval.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: sys.dm_os_wait_stats is cumulative since SQL Server start (or last DBCC SQLPERF clear).
  This query captures the raw snapshot with the server start time so analysts can detect restarts
  and discard invalid deltas. Do not compute pct_total_wait or avg_wait_ms here — those must be
  calculated against the delta between two snapshots, not against cumulative totals.
*/

SELECT
    GETDATE()                                           AS collection_time,
    @@SERVERNAME                                        AS server_name,
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS sqlserver_start_time,
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms                  AS resource_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
  AND wait_type NOT IN (
      -- Idle / background scheduler waits — not indicative of workload pressure
      'SLEEP_TASK',                     'SLEEP_SYSTEMTASK',
      'SLEEP_TEMPDBSTARTUP',            'SLEEP_DBSTARTUP',
      'SLEEP_DCOMSTARTUP',              'SLEEP_MASTERDBREADY',
      'SLEEP_MASTERMDREADY',            'SLEEP_MASTERUPGRADED',
      'SLEEP_MSDBSTARTUP',              'SNI_HTTP_ACCEPT',
      'DISPATCHER_QUEUE_SEMAPHORE',     'BROKER_TO_FLUSH',
      'BROKER_TASK_STOP',               'BROKER_EVENTHANDLER',
      'BROKER_RECEIVE_WAITFOR',         'CHECKPOINT_QUEUE',
      'DBMIRROR_EVENTS_QUEUE',          'DBMIRROR_WORKER_QUEUE',
      'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_BUFFER_FLUSH',
      'SQLTRACE_WAIT_ENTRIES',          'WAITFOR',
      'LAZYWRITER_SLEEP',               'LOGMGR_QUEUE',
      'ONDEMAND_TASK_QUEUE',            'REQUEST_FOR_DEADLOCK_SEARCH',
      'RESOURCE_QUEUE',                 'SERVER_IDLE_CHECK',
      'SP_SERVER_DIAGNOSTICS_SLEEP',    'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
      'XE_DISPATCHER_WAIT',             'XE_TIMER_EVENT',
      'HADR_WORK_QUEUE',                'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
      'HADR_CLUSAPI_CALL',              'HADR_NOTIFICATION_DEQUEUE',
      'FT_IFTS_SCHEDULER_IDLE_WAIT',    'FT_IFTSHC_MUTEX',
      'REPL_WORK_QUEUE',                'CLR_AUTO_EVENT',
      'CLR_MANUAL_EVENT',               'WAIT_XTP_COMPILE_WAIT'
  )
ORDER BY wait_time_ms DESC;
