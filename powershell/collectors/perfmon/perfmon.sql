/*
Script Name : perfmon
Category    : collectors
Purpose     : Snapshot SQL Server performance counters from sys.dm_os_performance_counters.
              Covers buffer pool, memory, throughput, connections, locks, and I/O.
              Cumulative rate counters require delta calculation between snapshots.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: cntr_type determines how to interpret cntr_value:
    65792  (PERF_COUNTER_LARGE_RAWCOUNT)  — point-in-time gauge, use directly
    272696576 (PERF_COUNTER_BULK_COUNT)   — cumulative counter, diff adjacent snapshots
    537003264 (PERF_LARGE_RAW_FRACTION)   — ratio numerator, needs the 'base' row
    1073939712 (PERF_LARGE_RAW_BASE)      — ratio denominator (e.g. cache hit ratio base)
  The cntr_type column is preserved so analysis can apply the correct formula.
*/

SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    RTRIM(object_name)                                              AS object_name,
    RTRIM(counter_name)                                             AS counter_name,
    RTRIM(instance_name)                                            AS instance_name,
    cntr_value,
    cntr_type
FROM sys.dm_os_performance_counters
WHERE
    -- Buffer pool / page cache
    (object_name LIKE '%Buffer Manager%' AND counter_name IN (
        'Buffer cache hit ratio', 'Buffer cache hit ratio base',
        'Page life expectancy',
        'Checkpoint pages/sec', 'Lazy writes/sec',
        'Page reads/sec', 'Page writes/sec',
        'Free pages', 'Database pages'))

    OR

    -- Memory manager
    (object_name LIKE '%Memory Manager%' AND counter_name IN (
        'Memory Grants Outstanding', 'Memory Grants Pending',
        'Target Server Memory (KB)', 'Total Server Memory (KB)',
        'Stolen Server Memory (KB)', 'Log Pool Memory (KB)'))

    OR

    -- SQL throughput
    (object_name LIKE '%SQL Statistics%' AND counter_name IN (
        'Batch Requests/sec', 'SQL Compilations/sec',
        'SQL Re-Compilations/sec', 'Auto-Param Attempts/sec'))

    OR

    -- Connections
    (object_name LIKE '%General Statistics%' AND counter_name IN (
        'User Connections', 'Logical Connections',
        'Active Temp Tables', 'Temp Tables Creation Rate'))

    OR

    -- Locks (_Total instance only to avoid per-lock-type noise)
    (object_name LIKE '%Locks%'
        AND instance_name = '_Total'
        AND counter_name IN (
            'Lock Waits/sec', 'Lock Wait Time (ms)',
            'Number of Deadlocks/sec', 'Lock Timeouts/sec'))

    OR

    -- Database-level counters (_Total)
    (object_name LIKE '%Databases%'
        AND instance_name = '_Total'
        AND counter_name IN (
            'Transactions/sec', 'Write Transactions/sec',
            'Log Bytes Flushed/sec', 'Log Flushes/sec',
            'Active Transactions'))

    OR

    -- Access methods / workfile creation
    (object_name LIKE '%Access Methods%' AND counter_name IN (
        'Table Lock Escalations/sec',
        'Worktables Created/sec', 'Worktable From Cache Ratio',
        'Worktable From Cache Base'))

    OR

    -- Plan cache
    (object_name LIKE '%Plan Cache%'
        AND instance_name = '_Total'
        AND counter_name IN (
            'Cache Hit Ratio', 'Cache Hit Ratio Base',
            'Cache Object Counts', 'Cache Pages'))

ORDER BY object_name, counter_name, instance_name;
