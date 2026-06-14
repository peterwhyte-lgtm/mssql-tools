/*
Script Name : Get-CdcAndChangeTracking
Category    : monitoring
Purpose     : CDC (Change Data Capture) and Change Tracking enabled databases with retention,
              cleanup settings, and latency indicators. Both features impact transaction log
              growth and can stall if cleanup jobs are absent or delayed.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE, SELECT on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

-- CDC: database-level enablement (from sys.databases) plus cleanup job presence
SELECT
    'CDC'                                               AS feature,
    d.name                                              AS database_name,
    d.is_cdc_enabled                                    AS feature_enabled,
    cj.job_type                                         AS job_type,
    cj.maxtrans                                         AS max_trans_per_scan,
    cj.maxscans                                         AS max_scans,
    cj.continuous                                       AS continuous_mode,
    cj.pollinginterval                                  AS polling_interval_sec,
    cj.retention                                        AS retention_minutes,
    CAST(cj.retention / 60.0 AS DECIMAL(10,1))         AS retention_hours,
    cj.threshold                                        AS cleanup_threshold,
    CASE
        WHEN d.is_cdc_enabled = 0
            THEN 'INFO — CDC not enabled on this database'
        WHEN cj.job_type = 'capture' AND cj.retention IS NULL
            THEN 'WARN — capture job exists but no cleanup job found; log growth risk'
        WHEN cj.retention < 1440
            THEN 'WARN — retention < 24 hours; downstream consumers may miss changes'
        ELSE 'OK'
    END                                                 AS status
FROM sys.databases AS d
LEFT JOIN msdb.dbo.cdc_jobs AS cj
    ON cj.database_id = d.database_id
WHERE d.database_id > 4
  AND (d.is_cdc_enabled = 1 OR cj.database_id IS NOT NULL)

UNION ALL

-- Change Tracking: server-level view available SQL 2008+
SELECT
    'CHANGE_TRACKING'                                   AS feature,
    DB_NAME(ct.database_id)                             AS database_name,
    1                                                   AS feature_enabled,
    NULL                                                AS job_type,
    NULL                                                AS max_trans_per_scan,
    NULL                                                AS max_scans,
    NULL                                                AS continuous_mode,
    NULL                                                AS polling_interval_sec,
    ct.retention_period * CASE ct.retention_period_units
                               WHEN 1 THEN 1
                               WHEN 2 THEN 60
                               WHEN 3 THEN 1440
                               ELSE 1
                           END                          AS retention_minutes,
    CAST(ct.retention_period * CASE ct.retention_period_units
                                    WHEN 1 THEN 1.0/60
                                    WHEN 2 THEN 1
                                    WHEN 3 THEN 24
                                    ELSE 1.0/60
                                END AS DECIMAL(10,1))   AS retention_hours,
    NULL                                                AS cleanup_threshold,
    CASE
        WHEN ct.retention_period * CASE ct.retention_period_units
                                        WHEN 1 THEN 1
                                        WHEN 2 THEN 60
                                        WHEN 3 THEN 1440
                                        ELSE 1
                                    END < 1440
            THEN 'WARN — retention < 24 hours; consumers may miss changes between syncs'
        ELSE 'OK — Change Tracking enabled'
    END                                                 AS status
FROM sys.change_tracking_databases AS ct

ORDER BY feature, database_name;
