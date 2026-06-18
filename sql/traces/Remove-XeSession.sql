/*
Script Name : Remove-XeSession
Category    : traces
Purpose     : Stops and drops a named Extended Events session. Run this when collection is complete.
              The .xel files on disk are NOT deleted — review them first with Get-XeSessionActivity.sql, then delete manually.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : ALTER ANY EVENT SESSION
*/
-- SAFE:WritesData
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Configuration — edit before running ────────────────────────────────── */
DECLARE @SessionName NVARCHAR(128) = N'DecommissionAudit';
/* ─────────────────────────────────────────────────────────────────────────── */

IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
BEGIN
    PRINT 'Session ' + @SessionName + ' does not exist — nothing to remove.';
    RETURN;
END;

DECLARE @sql NVARCHAR(MAX);

/* Stop first (ignore error if already stopped) */
BEGIN TRY
    SET @sql = N'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = STOP;';
    EXEC sp_executesql @sql;
END TRY
BEGIN CATCH
    /* Session was already stopped — that is fine */
END CATCH;

SET @sql = N'DROP EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER;';
EXEC sp_executesql @sql;

SELECT @SessionName AS session_removed, 'DROPPED' AS status;

PRINT 'Session ' + @SessionName + ' stopped and dropped.';
PRINT 'Note: .xel files on disk have NOT been deleted. Remove them manually when no longer needed.';
