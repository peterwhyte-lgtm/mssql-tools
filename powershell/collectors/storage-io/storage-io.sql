/*
Script Name : storage-io
Category    : collectors
Purpose     : Snapshot cumulative I/O stats per database file from
              sys.dm_io_virtual_file_stats. Diff adjacent snapshots to measure
              I/O activity and latency within each collection interval.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE, VIEW DATABASE STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: sys.dm_io_virtual_file_stats is cumulative since SQL Server start — the same
  delta model as wait stats and perfmon. Include sqlserver_start_time for restart detection.
  Latency ms values are derived from stall / number-of-ops. Where op count is 0, latency
  is NULL to avoid divide-by-zero. Analyse by diffing io_stall_read/write and
  num_of_reads/writes between snapshots to get interval latency.
*/

SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)          AS sqlserver_start_time,
    DB_NAME(vfs.database_id)                                        AS database_name,
    mf.physical_name,
    mf.type_desc                                                    AS file_type,
    vfs.database_id,
    vfs.file_id,
    -- Cumulative read metrics
    vfs.num_of_reads,
    vfs.num_of_bytes_read,
    vfs.io_stall_read_ms,
    -- Cumulative write metrics
    vfs.num_of_writes,
    vfs.num_of_bytes_written,
    vfs.io_stall_write_ms,
    -- Cumulative total stall
    vfs.io_stall,
    -- Point-in-time latency (derived — meaningful between snapshots when op count > 0)
    CASE WHEN vfs.num_of_reads  > 0
         THEN CAST(vfs.io_stall_read_ms  * 1.0 / vfs.num_of_reads  AS decimal(10,2))
         END                                                        AS avg_read_latency_ms,
    CASE WHEN vfs.num_of_writes > 0
         THEN CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS decimal(10,2))
         END                                                        AS avg_write_latency_ms,
    -- Current file size
    CAST(mf.size * 8.0 / 1024 AS decimal(10,2))                    AS file_size_mb
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id
   AND mf.file_id     = vfs.file_id
WHERE DB_NAME(vfs.database_id) IS NOT NULL   -- skip if database is being dropped
ORDER BY vfs.io_stall DESC;
