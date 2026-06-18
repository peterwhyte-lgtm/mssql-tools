/*
Script Name : Create-DecommissionAuditSession
Category    : traces
Purpose     : Creates an Extended Events session to capture all activity against a specific database — use before decommissioning or retiring a database to prove zero usage.
              Run for a minimum of 5-7 business days to catch batch jobs and end-of-period activity.
              Set STARTUP_STATE = ON so the session survives server restarts during collection.
              When done, run Remove-XeSession.sql to stop and clean up.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : ALTER ANY EVENT SESSION, VIEW SERVER STATE
*/
-- SAFE:CreatesObjects
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Configuration — edit these before running ───────────────────────────── */
DECLARE @SessionName  NVARCHAR(128) = N'DecommissionAudit';
DECLARE @DatabaseName NVARCHAR(128) = N'';   /* set to the database you are retiring; blank = all databases */
DECLARE @TraceFolder  NVARCHAR(260) = N'';   /* blank = auto-detect SQL Server log folder */
DECLARE @MaxFileMB    INT           = 100;
DECLARE @MaxFiles     INT           = 10;    /* 10 x 100 MB = up to 1 GB rolling */
/* ─────────────────────────────────────────────────────────────────────────── */

/* Auto-detect trace folder from SQL Server error log path if not supplied */
IF @TraceFolder = N''
BEGIN
    DECLARE @errlog NVARCHAR(260) = CAST(SERVERPROPERTY('ErrorLogFileName') AS NVARCHAR(260));
    SET @TraceFolder = LEFT(@errlog, LEN(@errlog) - CHARINDEX(N'\', REVERSE(@errlog)));
END;

DECLARE @FilePath NVARCHAR(260) = @TraceFolder + N'\' + @SessionName + N'.xel';

/* Build the WHERE predicate — filter by database name if one was supplied */
DECLARE @dbFilter NVARCHAR(500) = N'';
IF @DatabaseName <> N''
    SET @dbFilter = N'WHERE sqlserver.database_name = N''' + REPLACE(@DatabaseName, N'''', N'''''') + N'''';

DECLARE @sql NVARCHAR(MAX);

/* Drop if already exists so the script is safe to re-run */
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
BEGIN
    SET @sql = N'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = STOP;
    DROP EVENT SESSION '  + QUOTENAME(@SessionName) + N' ON SERVER;';
    EXEC sp_executesql @sql;
    PRINT 'Existing session ' + @SessionName + ' stopped and dropped.';
END;

SET @sql = N'
CREATE EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER

/* Capture T-SQL batch completions ----------------------------------------- */
ADD EVENT sqlserver.sql_batch_completed (
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.nt_username,
        sqlserver.database_name
    )
    ' + @dbFilter + N'
),

/* Capture stored procedure / RPC calls ------------------------------------ */
ADD EVENT sqlserver.rpc_completed (
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.nt_username,
        sqlserver.database_name
    )
    ' + @dbFilter + N'
),

/* Capture new logins ------------------------------------------------------- */
ADD EVENT sqlserver.login (
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.nt_username
    )
)

ADD TARGET package0.event_file (
    SET filename         = N''' + @FilePath + N''',
        max_file_size    = ' + CAST(@MaxFileMB AS NVARCHAR(10)) + N',
        max_rollover_files = ' + CAST(@MaxFiles AS NVARCHAR(10)) + N'
)
WITH (
    MAX_DISPATCH_LATENCY = 15 SECONDS,
    STARTUP_STATE        = ON    /* survives restarts — important for multi-day collection */
);

ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = START;';

EXEC sp_executesql @sql;

SELECT
    @SessionName  AS session_name,
    @FilePath     AS output_file,
    @DatabaseName AS database_filter,
    'RUNNING'     AS status;

PRINT 'Session ' + @SessionName + ' created and started.';
PRINT 'Output file: ' + @FilePath;
PRINT 'Run Get-XeSessionActivity.sql to review collected data.';
PRINT 'Run Remove-XeSession.sql when collection is complete.';
