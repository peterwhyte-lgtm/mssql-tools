/*
Script Name : query-store
Category    : collectors
Purpose     : Captures top 50 queries by average CPU time from the most recently
              completed Query Store interval. Run per-database with Query Store enabled.
              Build a historical record to detect plan regressions and CPU trend changes.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW DATABASE STATE; Query Store must be enabled in the target database
              Run with: -Database YourDatabase
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: Query Store data is per-database. This script runs in the context of a
  specific user database and captures the top queries from the most recently
  completed runtime stats interval. The wrapper iterates all QS-enabled databases.
  If QS is not enabled, returns a single status row so the collector never fails.

  Interval selection: we pick the most recent rsi.end_time that is in the past
  (completed interval) to avoid partial data from the active interval.
*/

IF NOT EXISTS (
    SELECT 1 FROM sys.database_query_store_options
    WHERE desired_state_desc = 'READ_WRITE'
       OR desired_state_desc = 'READ_ONLY'
)
BEGIN
    SELECT
        GETDATE()       AS collection_time,
        @@SERVERNAME    AS server_name,
        DB_NAME()       AS database_name,
        NULL            AS query_id,
        'QUERY_STORE_DISABLED' AS query_sql_text,
        NULL AS plan_id, NULL AS query_plan_hash,
        NULL AS interval_start, NULL AS interval_end,
        NULL AS count_executions,
        NULL AS avg_cpu_ms, NULL AS avg_duration_ms,
        NULL AS avg_logical_io_reads, NULL AS avg_rowcount,
        NULL AS is_forced_plan, NULL AS plan_forcing_type_desc;
    RETURN;
END

DECLARE @latest_interval_id BIGINT;
SELECT TOP 1 @latest_interval_id = runtime_stats_interval_id
FROM sys.query_store_runtime_stats_interval
WHERE end_time < GETDATE()
ORDER BY end_time DESC;

IF @latest_interval_id IS NULL
BEGIN
    SELECT GETDATE() AS collection_time, @@SERVERNAME AS server_name,
           DB_NAME() AS database_name, NULL AS query_id,
           'NO_COMPLETED_INTERVAL' AS query_sql_text,
           NULL AS plan_id, NULL AS query_plan_hash,
           NULL AS interval_start, NULL AS interval_end,
           NULL AS count_executions, NULL AS avg_cpu_ms,
           NULL AS avg_duration_ms, NULL AS avg_logical_io_reads,
           NULL AS avg_rowcount, NULL AS is_forced_plan,
           NULL AS plan_forcing_type_desc;
    RETURN;
END

SELECT TOP 50
    GETDATE()                                           AS collection_time,
    @@SERVERNAME                                        AS server_name,
    DB_NAME()                                           AS database_name,
    q.query_id,
    LEFT(REPLACE(REPLACE(qt.query_sql_text, CHAR(13), ' '), CHAR(10), ' '), 500)
                                                        AS query_sql_text,
    p.plan_id,
    CONVERT(char(32), p.query_plan_hash, 2)             AS query_plan_hash,
    rsi.start_time                                      AS interval_start,
    rsi.end_time                                        AS interval_end,
    rs.count_executions,
    CAST(rs.avg_cpu_time    / 1000.0 AS decimal(12,2)) AS avg_cpu_ms,
    CAST(rs.avg_duration    / 1000.0 AS decimal(12,2)) AS avg_duration_ms,
    rs.avg_logical_io_reads,
    CAST(rs.avg_rowcount             AS bigint)         AS avg_rowcount,
    p.is_forced_plan,
    p.plan_forcing_type_desc
FROM sys.query_store_query          q
JOIN sys.query_store_query_text     qt  ON qt.query_text_id           = q.query_text_id
JOIN sys.query_store_plan           p   ON p.query_id                 = q.query_id
JOIN sys.query_store_runtime_stats  rs  ON rs.plan_id                 = p.plan_id
                                       AND rs.runtime_stats_interval_id = @latest_interval_id
JOIN sys.query_store_runtime_stats_interval rsi
    ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE q.is_internal_query = 0
ORDER BY rs.avg_cpu_time DESC;
