/*
Script Name : Kill-BlockingSession
Category    : lab
Purpose     : Template for terminating a blocking session after confirming it is
              safe to do so. Always run Get-BlockingChains first to identify the
              head blocker and understand the impact before killing anything.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Writes data
Impact      : High  *** CONFIRM SESSION ID AND INTENT BEFORE RUNNING ***
Requires    : ALTER ANY CONNECTION (or sysadmin)
*/
-- SAFE:WritesData
-- IMPACT:High
-- LAB:ManualOnly

/*
  ===================================================================
   BEFORE KILLING A SESSION:

   1. Run Get-BlockingChains to identify the head blocker (the session
      at the top of the chain — not the victims).

   2. Confirm the session is not a legitimate long-running process
      (backups, ETL, bulk loads).

   3. Check what the session is running:
      SELECT text FROM sys.dm_exec_requests r
      CROSS APPLY sys.dm_exec_sql_text(r.sql_handle)
      WHERE r.session_id = <spid>;

   4. Check who owns it:
      SELECT login_name, host_name, program_name
      FROM sys.dm_exec_sessions
      WHERE session_id = <spid>;

   5. Only then kill it. SQL Server rolls back the open transaction
      automatically — rollback time is proportional to how much work
      the session has done.
  ===================================================================
*/

-- Set the session ID to kill (the HEAD BLOCKER from Get-BlockingChains)
DECLARE @spid INT = NULL;  -- ← replace NULL with the session_id to kill

-- Safety check: confirm the session exists and is blocking before proceeding
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time / 1000          AS wait_seconds,
    r.status,
    t.text                      AS current_statement
FROM       sys.dm_exec_sessions     s
LEFT JOIN  sys.dm_exec_requests     r  ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.session_id = @spid;

-- Review the row above, then highlight and run only the KILL below
-- when you are certain this is the correct session.

-- KILL @spid;  -- ← un-comment this line only after confirming above
