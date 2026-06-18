/*
Script Name : Create-LoginActivitySession
Category    : traces
Purpose     : Creates a lightweight Extended Events session that captures every successful login to the server — who, from where, and using which application.
              Use to answer "who connects to this server" before decommissioning, during security reviews, or to baseline connection patterns.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : ALTER ANY EVENT SESSION, VIEW SERVER STATE
*/
-- SAFE:CreatesObjects
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Configuration — edit these before running ───────────────────────────── */
DECLARE @SessionName NVARCHAR(128) = N'LoginActivity';
DECLARE @TraceFolder NVARCHAR(260) = N'';   /* blank = auto-detect SQL Server log folder */
DECLARE @MaxFileMB   INT           = 50;
DECLARE @MaxFiles    INT           = 14;    /* 14 x 50 MB rolling — ~7 days at typical load */
/* ─────────────────────────────────────────────────────────────────────────── */

IF @TraceFolder = N''
BEGIN
    DECLARE @errlog NVARCHAR(260) = CAST(SERVERPROPERTY('ErrorLogFileName') AS NVARCHAR(260));
    SET @TraceFolder = LEFT(@errlog, LEN(@errlog) - CHARINDEX(N'\', REVERSE(@errlog)));
END;

DECLARE @FilePath NVARCHAR(260) = @TraceFolder + N'\' + @SessionName + N'.xel';
DECLARE @sql      NVARCHAR(MAX);

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
BEGIN
    SET @sql = N'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = STOP;
    DROP EVENT SESSION '  + QUOTENAME(@SessionName) + N' ON SERVER;';
    EXEC sp_executesql @sql;
    PRINT 'Existing session ' + @SessionName + ' stopped and dropped.';
END;

SET @sql = N'
CREATE EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER
ADD EVENT sqlserver.login (
    WHERE sqlserver.is_system = 0   /* exclude internal SQL Server logins */
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.nt_username,
        sqlserver.server_principal_name,
        sqlserver.database_name
    )
)
ADD TARGET package0.event_file (
    SET filename           = N''' + @FilePath + N''',
        max_file_size      = ' + CAST(@MaxFileMB AS NVARCHAR(10)) + N',
        max_rollover_files = ' + CAST(@MaxFiles  AS NVARCHAR(10)) + N'
)
WITH (
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    STARTUP_STATE        = ON
);
ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = START;';

EXEC sp_executesql @sql;

SELECT
    @SessionName AS session_name,
    @FilePath    AS output_file,
    'RUNNING'    AS status;

PRINT 'Session ' + @SessionName + ' created and started.';
PRINT 'Output file: ' + @FilePath;
