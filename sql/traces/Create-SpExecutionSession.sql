/*
Script Name : Create-SpExecutionSession
Category    : traces
Purpose     : Creates an Extended Events session capturing stored procedure and RPC execution — procedure name, duration, login, and hostname.
              Use to profile what procedures are called most often, by whom, and how long they take — especially useful before a migration or decommission.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : ALTER ANY EVENT SESSION, VIEW SERVER STATE
*/
-- SAFE:CreatesObjects
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Configuration — edit these before running ───────────────────────────── */
DECLARE @SessionName  NVARCHAR(128) = N'SpExecution';
DECLARE @DatabaseName NVARCHAR(128) = N'';   /* blank = all databases */
DECLARE @TraceFolder  NVARCHAR(260) = N'';   /* blank = auto-detect SQL Server log folder */
DECLARE @MaxFileMB    INT           = 100;
DECLARE @MaxFiles     INT           = 7;
/* ─────────────────────────────────────────────────────────────────────────── */

IF @TraceFolder = N''
BEGIN
    DECLARE @errlog NVARCHAR(260) = CAST(SERVERPROPERTY('ErrorLogFileName') AS NVARCHAR(260));
    SET @TraceFolder = LEFT(@errlog, LEN(@errlog) - CHARINDEX(N'\', REVERSE(@errlog)));
END;

DECLARE @FilePath NVARCHAR(260) = @TraceFolder + N'\' + @SessionName + N'.xel';

DECLARE @dbFilter NVARCHAR(500) = N'';
IF @DatabaseName <> N''
    SET @dbFilter = N'WHERE sqlserver.database_name = N''' + REPLACE(@DatabaseName, N'''', N'''''') + N'''';

DECLARE @sql NVARCHAR(MAX);

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
BEGIN
    SET @sql = N'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = STOP;
    DROP EVENT SESSION '  + QUOTENAME(@SessionName) + N' ON SERVER;';
    EXEC sp_executesql @sql;
    PRINT 'Existing session ' + @SessionName + ' stopped and dropped.';
END;

SET @sql = N'
CREATE EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER
ADD EVENT sqlserver.rpc_completed (
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.database_name
    )
    ' + @dbFilter + N'
)
ADD TARGET package0.event_file (
    SET filename           = N''' + @FilePath + N''',
        max_file_size      = ' + CAST(@MaxFileMB AS NVARCHAR(10)) + N',
        max_rollover_files = ' + CAST(@MaxFiles  AS NVARCHAR(10)) + N'
)
WITH (
    MAX_DISPATCH_LATENCY = 15 SECONDS,
    STARTUP_STATE        = ON
);
ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = START;';

EXEC sp_executesql @sql;

SELECT
    @SessionName  AS session_name,
    @FilePath     AS output_file,
    @DatabaseName AS database_filter,
    'RUNNING'     AS status;
