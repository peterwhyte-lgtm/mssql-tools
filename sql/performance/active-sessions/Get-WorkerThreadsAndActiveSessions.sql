/*
Script Name : Get-WorkerThreadsAndActiveSessions
Category    : performance-troubleshooting
Purpose     : Active user sessions with CPU, elapsed time, and current worker thread pool usage.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- Get SQL worker threads
SELECT 
    SUM(current_workers_count) AS current_worker_threads
FROM sys.dm_os_schedulers;
