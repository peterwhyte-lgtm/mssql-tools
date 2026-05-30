/*
Script Name : tempdb
Category    : collectors
Purpose     : Snapshot TempDB file-level space usage and top session consumers.
              Tracks version store pressure, internal vs user object splits,
              and per-file free space for contention analysis.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE, VIEW DATABASE STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: Two result sets in one query using UNION ALL.
  Section 1 — file-level: one row per TempDB data/log file with space breakdown.
  Section 2 — top sessions: top 10 sessions by current TempDB allocation.
  Both sections share collection_time and server_name for join-ability.
  row_type column distinguishes the two sections.
*/

-- Section 1: file-level space (from tempdb context)
SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    'file'                                                          AS row_type,
    f.name                                                          AS file_name,
    f.physical_name,
    f.type_desc                                                     AS file_type,
    CAST(f.size * 8.0 / 1024 AS decimal(10,2))                     AS file_size_mb,
    CAST(fu.total_page_count   * 8.0 / 1024 AS decimal(10,2))      AS total_allocated_mb,
    CAST(fu.unallocated_extent_page_count * 8.0 / 1024 AS decimal(10,2)) AS free_mb,
    CAST(fu.user_object_reserved_page_count  * 8.0 / 1024 AS decimal(10,2)) AS user_objects_mb,
    CAST(fu.internal_object_reserved_page_count * 8.0 / 1024 AS decimal(10,2)) AS internal_objects_mb,
    CAST(fu.version_store_reserved_page_count * 8.0 / 1024 AS decimal(10,2)) AS version_store_mb,
    CAST(fu.mixed_extent_page_count  * 8.0 / 1024 AS decimal(10,2)) AS mixed_extents_mb,
    NULL                                                            AS session_id,
    NULL                                                            AS login_name,
    NULL                                                            AS host_name,
    NULL                                                            AS program_name,
    NULL AS session_user_objects_mb,
    NULL AS session_internal_objects_mb
FROM tempdb.sys.dm_db_file_space_usage fu
JOIN tempdb.sys.database_files f ON f.file_id = fu.file_id

UNION ALL

-- Section 2: top 10 TempDB consumers (current session allocations)
SELECT TOP 10
    GETDATE(),
    @@SERVERNAME,
    'session',
    NULL, NULL,
    NULL,
    NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    su.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    CAST((su.user_objects_alloc_page_count - su.user_objects_dealloc_page_count) * 8.0 / 1024 AS decimal(10,2)),
    CAST((su.internal_objects_alloc_page_count - su.internal_objects_dealloc_page_count) * 8.0 / 1024 AS decimal(10,2))
FROM sys.dm_db_session_space_usage su
JOIN sys.dm_exec_sessions s ON s.session_id = su.session_id
WHERE su.session_id > 50  -- exclude system sessions
  AND (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) > 0
ORDER BY (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) DESC;
