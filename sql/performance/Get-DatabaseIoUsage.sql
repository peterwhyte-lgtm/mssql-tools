/*
Script Name : Get-DatabaseIoUsage
Category    : performance-troubleshooting
Purpose     : Database I/O totals with read and write latency — primary tool for I/O pressure triage.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
Notes       : Counters accumulate since last SQL Server restart. Latency > 20ms (read) or
              > 10ms (write) on data files warrants investigation.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH io_stats AS (
    SELECT
        vfs.database_id,
        SUM(vfs.num_of_reads)          AS reads,
        SUM(vfs.num_of_bytes_read)     AS bytes_read,
        SUM(vfs.num_of_writes)         AS writes,
        SUM(vfs.num_of_bytes_written)  AS bytes_written,
        SUM(vfs.io_stall_read_ms)      AS io_stall_read_ms,
        SUM(vfs.io_stall_write_ms)     AS io_stall_write_ms
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    GROUP BY vfs.database_id
)
SELECT
    DB_NAME(database_id)                                                    AS database_name,
    reads,
    CAST(bytes_read    / 1024.0 / 1024 AS DECIMAL(18,1))                  AS read_mb,
    CAST(io_stall_read_ms  / NULLIF(reads,  0) AS DECIMAL(10,1))          AS read_latency_ms,
    writes,
    CAST(bytes_written / 1024.0 / 1024 AS DECIMAL(18,1))                  AS write_mb,
    CAST(io_stall_write_ms / NULLIF(writes, 0) AS DECIMAL(10,1))          AS write_latency_ms,
    io_stall_read_ms + io_stall_write_ms                                    AS total_stall_ms
FROM io_stats
WHERE database_id > 4
ORDER BY total_stall_ms DESC;
