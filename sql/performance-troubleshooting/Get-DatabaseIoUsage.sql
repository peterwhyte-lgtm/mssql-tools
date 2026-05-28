/*
Script Name : I/O Usage by Database
Description : Returns total read and write activity per database from file I/O statistics.
Author      : Peter Whyte (https://sqldba.blog)
*/

WITH io_stats AS
(
    SELECT
        vfs.database_id,
        SUM(vfs.num_of_reads) AS reads,
        SUM(vfs.num_of_bytes_read) AS bytes_read,
        SUM(vfs.num_of_writes) AS writes,
        SUM(vfs.num_of_bytes_written) AS bytes_written
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    GROUP BY vfs.database_id
)
SELECT
    DB_NAME(io_stats.database_id) AS database_name,
    io_stats.reads,
    CAST(io_stats.bytes_read / 1024.0 / 1024 AS DECIMAL(18,2)) AS read_mb,
    io_stats.writes,
    CAST(io_stats.bytes_written / 1024.0 / 1024 AS DECIMAL(18,2)) AS write_mb
FROM io_stats
ORDER BY io_stats.bytes_read + io_stats.bytes_written DESC;
