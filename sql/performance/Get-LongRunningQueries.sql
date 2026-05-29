/*
Script Name : Get-LongRunningQueries
Category    : performance-troubleshooting
Purpose     : Active requests running longer than expected — ordered by elapsed time descending.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;

SELECT
    r.session_id,
    DB_NAME(r.database_id)                                                  AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status,
    CAST(r.total_elapsed_time / 1000.0 AS DECIMAL(10,1))                   AS elapsed_sec,
    CAST(r.cpu_time           / 1000.0 AS DECIMAL(10,1))                   AS cpu_sec,
    r.logical_reads,
    r.writes,
    r.wait_type,
    CAST(r.wait_time / 1000.0 AS DECIMAL(10,1))                            AS wait_sec,
    r.blocking_session_id,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        CASE r.statement_end_offset
            WHEN -1 THEN LEN(t.text)
            ELSE (r.statement_end_offset - r.statement_start_offset) / 2
        END
    )                                                                       AS current_statement
FROM sys.dm_exec_requests       AS r
JOIN sys.dm_exec_sessions        AS s  ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID
  AND r.status      <> 'sleeping'
ORDER BY r.total_elapsed_time DESC;
