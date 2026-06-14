/*
Script Name : vlf-count
Category    : collectors
Purpose     : Point-in-time snapshot of Virtual Log File counts per database. High VLF
              counts slow log backup, restore, and recovery. Collect daily to catch
              databases accumulating VLFs before they become a maintenance emergency.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE; VIEW DATABASE STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: sys.dm_db_log_info (SQL Server 2016+) returns one row per VLF per database.
  We aggregate to one row per database with the count. log_reuse_wait_desc explains
  why the log cannot reuse space — critical context when VLFs are high.
  Thresholds (rule of thumb):
    < 100    OK
    100-999  Monitor
    1000+    WARNING — consider log backup and shrink cycle to reclaim VLFs
    10000+   CRITICAL — recovery and log backup significantly impacted
*/

SELECT
    GETDATE()                                           AS collection_time,
    @@SERVERNAME                                        AS server_name,
    d.name                                              AS database_name,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    COUNT(li.file_id)                                   AS vlf_count,
    CAST(mf.size * 8.0 / 1024 AS decimal(10,2))        AS log_file_size_mb,
    CASE
        WHEN COUNT(li.file_id) >= 10000 THEN 'CRITICAL'
        WHEN COUNT(li.file_id) >= 1000  THEN 'WARNING'
        WHEN COUNT(li.file_id) >= 100   THEN 'MONITOR'
        ELSE 'OK'
    END                                                 AS vlf_status
FROM sys.databases d
JOIN sys.master_files mf
    ON mf.database_id = d.database_id
    AND mf.type = 1   -- LOG files only
CROSS APPLY sys.dm_db_log_info(d.database_id) li
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4
GROUP BY d.name, d.recovery_model_desc, d.log_reuse_wait_desc, mf.size
ORDER BY vlf_count DESC;
