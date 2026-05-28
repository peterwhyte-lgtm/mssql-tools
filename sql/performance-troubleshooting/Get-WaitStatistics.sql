-- Top wait statistics for the current instance.
-- Useful for identifying bottlenecks during performance investigations.

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;
