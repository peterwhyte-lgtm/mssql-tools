/*
Script Name : Get-WorkerThreadsAndActiveSessions
Category    : performance-troubleshooting
Purpose     : Active user sessions with CPU, elapsed time, and current worker thread pool usage.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;

SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(s.database_id)                                                      AS database_name,
    ISNULL(r.status, s.status)                                                  AS status,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000.0 AS DECIMAL(10,1))            AS elapsed_sec,
    CAST(ISNULL(r.cpu_time, 0)           / 1000.0 AS DECIMAL(10,1))            AS cpu_sec,
    r.wait_type,
    r.blocking_session_id,
    (SELECT SUM(current_workers_count)
     FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE')                AS current_worker_threads,
    (SELECT max_workers_count FROM sys.dm_os_sys_info)                          AS max_worker_threads
FROM sys.dm_exec_sessions    AS s
LEFT JOIN sys.dm_exec_requests AS r ON s.session_id = r.session_id
WHERE s.is_user_process = 1
ORDER BY ISNULL(r.total_elapsed_time, 0) DESC;
