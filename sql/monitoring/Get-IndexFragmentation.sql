/*
Script Name : Get-IndexFragmentation
Category    : maintenance-and-reliability
Purpose     : Top fragmented indexes across all user databases, ranked by fragmentation pct.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Medium
Requires    : VIEW SERVER STATE
Notes       : Iterates every online user database and collects into a single result set.
              Uses LIMITED scan mode — faster than SAMPLED/DETAILED but still proportional
              to database size. Expect 30 s to several minutes on busy or large instances.
              Indexes under 1000 pages are excluded; fragmentation threshold is 10%.
              Run off-peak where possible.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Medium

CREATE TABLE #frag (
    database_name      sysname         NOT NULL,
    schema_name        sysname         NOT NULL,
    table_name         sysname         NOT NULL,
    index_name         sysname         NOT NULL,
    index_type         nvarchar(60)    NOT NULL,
    fragmentation_pct  decimal(5,1)    NOT NULL,
    page_count         bigint          NOT NULL,
    recommended_action varchar(10)     NOT NULL
);

DECLARE @sql nvarchar(max) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #frag
    (database_name, schema_name, table_name, index_name,
     index_type, fragmentation_pct, page_count, recommended_action)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    i.type_desc,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1)),
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN ''REBUILD''
        WHEN ips.avg_fragmentation_in_percent >= 10 THEN ''REORGANIZE''
    END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ips
JOIN sys.indexes AS i ON  ips.object_id = i.object_id
                      AND ips.index_id  = i.index_id
JOIN sys.tables  AS t ON  i.object_id   = t.object_id
JOIN sys.schemas AS s ON  t.schema_id   = s.schema_id
WHERE i.name IS NOT NULL
  AND ips.page_count                   >= 1000
  AND ips.avg_fragmentation_in_percent >= 10;
'
FROM sys.databases
WHERE state_desc  = 'ONLINE'
  AND database_id > 4;

IF LEN(@sql) > 0
    EXEC sys.sp_executesql @sql;

SELECT
    database_name,
    schema_name,
    table_name,
    index_name,
    index_type,
    fragmentation_pct,
    page_count,
    recommended_action
FROM   #frag
ORDER BY fragmentation_pct DESC;

DROP TABLE #frag;
