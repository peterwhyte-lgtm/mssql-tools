/*
Script Name : Generate-UserMappingScript
Category    : migration
Purpose     : Generate CREATE USER and role membership DDL for all user databases.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, VIEW DEFINITION on each database
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

DECLARE @ddl    NVARCHAR(MAX) = N'';
DECLARE @crlf   NCHAR(2)     = CHAR(13) + CHAR(10);
DECLARE @dbname NVARCHAR(128);
DECLARE @chunk  NVARCHAR(MAX);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- Database User and Role Mapping Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- Run on TARGET server after logins are created and databases restored.' + @crlf
    + N'-- sp_change_dbowner is called where needed to fix orphaned dbo mapping.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = N'ONLINE'
      AND is_read_only = 0
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @chunk = N'';

    -- Build the per-database DDL using dynamic SQL (avoids cross-db restrictions)
    DECLARE @q NVARCHAR(MAX) = N'
    DECLARE @db_ddl NVARCHAR(MAX) = N'''';
    DECLARE @cr NCHAR(2) = CHAR(13) + CHAR(10);

    -- Users (exclude built-ins)
    SELECT @db_ddl = @db_ddl
        + N''IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N'''''' + REPLACE(dp.name, N'''''''', N'''''''''''') + N'''''')'' + @cr
        + CASE
            WHEN dp.type = ''S'' AND dp.sid IS NOT NULL AND EXISTS (
                SELECT 1 FROM sys.server_principals sp WHERE sp.sid = dp.sid)
            THEN N''    CREATE USER ['' + dp.name + N''] FOR LOGIN ['' + SUSER_SNAME(dp.sid) + N'']''
            WHEN dp.type = ''S'' AND dp.authentication_type_desc = ''DATABASE''
            THEN N''    CREATE USER ['' + dp.name + N''] WITHOUT LOGIN''
            WHEN dp.type IN (''U'', ''G'')
            THEN N''    CREATE USER ['' + dp.name + N''] FOR LOGIN ['' + dp.name + N'']''
            ELSE N''    -- SKIP: '' + dp.name
          END + @cr
        + N''GO'' + @cr + @cr
    FROM [' + @dbname + N'].sys.database_principals dp
    WHERE dp.type IN (''S'', ''U'', ''G'')
      AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'', ''public'')
      AND dp.name NOT LIKE N''##%##''
    ORDER BY dp.name;

    -- Role memberships (skip public/dbo)
    SELECT @db_ddl = @db_ddl
        + N''IF EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N'''''' + REPLACE(m.name, N'''''''', N'''''''''''') + N'''''')'' + @cr
        + N''    ALTER ROLE ['' + r.name + N''] ADD MEMBER ['' + m.name + N''];'' + @cr
        + N''GO'' + @cr + @cr
    FROM [' + @dbname + N'].sys.database_role_members drm
    INNER JOIN [' + @dbname + N'].sys.database_principals r ON drm.role_principal_id   = r.principal_id
    INNER JOIN [' + @dbname + N'].sys.database_principals m ON drm.member_principal_id  = m.principal_id
    WHERE r.name <> N''public''
      AND m.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'', ''public'')
      AND m.name NOT LIKE N''##%##''
    ORDER BY r.name, m.name;

    SELECT @db_ddl AS chunk;
    ';

    EXEC sp_executesql @q, N'', @chunk OUTPUT;

    -- Fallback: sp_executesql with OUTPUT doesn't work across DB — use a temp table
    IF @chunk IS NULL OR @chunk = N''
    BEGIN
        IF OBJECT_ID('tempdb..#chunk') IS NOT NULL DROP TABLE #chunk;
        CREATE TABLE #chunk (chunk NVARCHAR(MAX));
        INSERT INTO #chunk
        EXEC sp_executesql @q;
        SELECT @chunk = chunk FROM #chunk;
        DROP TABLE #chunk;
    END

    IF @chunk IS NOT NULL AND @chunk <> N''
    BEGIN
        SET @ddl = @ddl
            + N'-- ── Database: [' + @dbname + N'] ──────────────────────────────' + @crlf
            + N'USE [' + @dbname + N'];' + @crlf
            + N'GO' + @crlf + @crlf
            + @chunk;
    END

    FETCH NEXT FROM db_cur INTO @dbname;
END

CLOSE db_cur;
DEALLOCATE db_cur;

SELECT @ddl AS ddl;
