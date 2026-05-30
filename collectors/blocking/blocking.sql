/*
Script Name : blocking
Category    : collectors
Purpose     : Capture active blocking chains with head blocker, victim, wait info,
              and current SQL text. Returns rows only when blocking exists.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: Only returns rows when blocking_session_id > 0. The collector wrapper
  checks row count before writing to CSV so files stay clean on quiet servers.
  Captures the full chain: head blocker + all downstream victims.
*/

WITH blocking_chain AS (
    SELECT
        r.session_id                                                AS blocked_spid,
        r.blocking_session_id                                       AS blocking_spid,
        r.wait_type,
        r.wait_time                                                 AS wait_time_ms,
        r.wait_resource,
        r.status,
        r.command,
        r.database_id,
        r.open_transaction_count,
        r.cpu_time,
        r.total_elapsed_time                                        AS elapsed_ms,
        s.login_name,
        s.host_name,
        s.program_name,
        s.login_time,
        r.sql_handle,
        r.plan_handle
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions  s ON s.session_id = r.session_id
    WHERE r.blocking_session_id > 0
)
SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    bc.blocked_spid,
    bc.blocking_spid,
    -- Identify head blocker (a blocker who is not itself blocked)
    CASE WHEN NOT EXISTS (
            SELECT 1 FROM sys.dm_exec_requests r2
            WHERE r2.session_id = bc.blocking_spid
              AND r2.blocking_session_id > 0)
         THEN 1 ELSE 0 END                                          AS is_head_blocker,
    bc.wait_type,
    bc.wait_time_ms,
    bc.wait_resource,
    bc.status,
    bc.command,
    DB_NAME(bc.database_id)                                         AS database_name,
    bc.open_transaction_count,
    bc.elapsed_ms,
    bc.login_name,
    bc.host_name,
    bc.program_name,
    -- Current SQL text of the blocked session
    SUBSTRING(
        REPLACE(REPLACE(st_blocked.text, CHAR(13), ' '), CHAR(10), ' '),
        (bc.blocked_spid % 128) + 1,
        1000)                                                       AS blocked_statement,
    -- Current SQL text of the blocking session (may be idle — shows last statement)
    SUBSTRING(
        REPLACE(REPLACE(ISNULL(st_blocker.text, '(no active request)'), CHAR(13), ' '), CHAR(10), ' '),
        1, 500)                                                     AS blocker_last_statement
FROM blocking_chain bc
OUTER APPLY sys.dm_exec_sql_text(bc.sql_handle)  AS st_blocked
OUTER APPLY (
    SELECT TOP 1 st2.text
    FROM sys.dm_exec_requests r2
    OUTER APPLY sys.dm_exec_sql_text(r2.sql_handle) AS st2
    WHERE r2.session_id = bc.blocking_spid
) AS st_blocker
ORDER BY bc.blocking_spid, bc.wait_time_ms DESC;
