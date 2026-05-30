/*
Script Name : database-growth
Category    : collectors
Purpose     : Point-in-time snapshot of database file sizes, free space, and
              autogrowth settings. Diff adjacent snapshots to measure growth
              rate and forecast when files will hit their configured limits.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: One row per database file. This is point-in-time (not cumulative) so each
  snapshot is standalone — no delta calculation required. Compare file_size_mb across
  snapshots to measure growth. The growth_limit_mb column is NULL for unlimited files
  (max_size = -1 or 268435456 pages = 2TB physical limit).
*/

SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    d.name                                                          AS database_name,
    d.state_desc                                                    AS database_state,
    d.recovery_model_desc,
    mf.name                                                         AS logical_name,
    mf.physical_name,
    mf.type_desc                                                    AS file_type,
    -- Current file size
    CAST(mf.size * 8.0 / 1024 AS decimal(10,2))                    AS file_size_mb,
    -- Free space within the file (requires USE context — approximate via size - used)
    -- For data files: use FILEPROPERTY; for all files use sys.dm_db_file_space_usage in tempdb
    -- Here we use size vs max_size as a planning metric rather than internal fragmentation
    CASE WHEN mf.max_size IN (-1, 268435456)
         THEN NULL
         ELSE CAST((mf.max_size - mf.size) * 8.0 / 1024 AS decimal(10,2))
         END                                                        AS space_to_limit_mb,
    -- Autogrowth settings
    CASE WHEN mf.is_percent_growth = 1
         THEN CAST(mf.growth AS varchar(10)) + '%'
         ELSE CAST(mf.growth * 8 / 1024 AS varchar(10)) + ' MB'
         END                                                        AS autogrowth,
    mf.is_percent_growth,
    -- Max size (NULL = unlimited)
    CASE WHEN mf.max_size IN (-1, 268435456)
         THEN NULL
         ELSE CAST(mf.max_size * 8.0 / 1024 AS decimal(10,2))
         END                                                        AS growth_limit_mb,
    -- Risk flag consistent with Get-DatabaseGrowthRisk.sql
    CASE
        WHEN mf.max_size IN (-1, 268435456) THEN 'UNLIMITED'
        WHEN mf.size >= mf.max_size         THEN 'AT_LIMIT'
        WHEN (mf.max_size - mf.size) * 8.0 / 1024 < 1024
             AND mf.max_size NOT IN (-1, 268435456) THEN 'NEAR_LIMIT'
        ELSE 'OK'
    END                                                             AS growth_status
FROM sys.master_files mf
JOIN sys.databases    d  ON d.database_id = mf.database_id
WHERE d.state_desc = 'ONLINE'
ORDER BY d.name, mf.type_desc, mf.name;
