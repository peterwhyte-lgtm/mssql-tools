/*
Script Name : Get-FailedLoginSummary
Category    : security
Purpose     : Aggregated failed login analysis from the security ring buffer and current
              lockout state per SQL login. Surfaces brute-force patterns and locked accounts
              without scanning the full error log. Complements Get-WeakLoginSettings (which
              checks policy configuration) — this checks what is actually happening.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE, sysadmin (for LOGINPROPERTY on other logins)
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

-- Materialise XML parsing first — XML method calls are not allowed in GROUP BY
WITH ring_events AS (
    SELECT CAST(record AS XML) AS rec
    FROM   sys.dm_os_ring_buffers
    WHERE  ring_buffer_type = 'RING_BUFFER_SECURITY_ERROR'
),
parsed AS (
    SELECT
        rec.value('(//LoginRecord/LoginName)[1]',  'NVARCHAR(128)') AS login_name,
        rec.value('(//LoginRecord/ClientHost)[1]', 'NVARCHAR(256)') AS client_host,
        rec.value('(//Error)[1]',                  'INT')           AS error_code,
        rec.value('(/Record/@time)[1]',            'BIGINT')        AS ring_time_ms
    FROM ring_events
),
aggregated AS (
    SELECT
        login_name,
        client_host,
        error_code,
        COUNT(*)            AS failure_count,
        MIN(ring_time_ms)   AS first_ring_ms,
        MAX(ring_time_ms)   AS last_ring_ms
    FROM parsed
    GROUP BY login_name, client_host, error_code
)
SELECT
    agg.login_name,
    agg.client_host,
    agg.error_code,
    CASE agg.error_code
        WHEN 18456 THEN 'Login failed (bad password or login does not exist)'
        WHEN 18452 THEN 'Login from untrusted domain or cannot use Windows auth'
        WHEN 18451 THEN 'Login failed — only admin connections are allowed'
        WHEN 18470 THEN 'Account is disabled'
        WHEN 18488 THEN 'Password must be changed'
        WHEN  4818 THEN 'Password does not meet complexity requirements'
        ELSE            'Error ' + CAST(agg.error_code AS VARCHAR(10))
    END                                                             AS error_description,
    agg.failure_count,
    -- Approximate wall-clock time from ring buffer offset
    DATEADD(ms, agg.first_ring_ms - si.ms_ticks, GETDATE())        AS first_failure_approx,
    DATEADD(ms, agg.last_ring_ms  - si.ms_ticks, GETDATE())        AS last_failure_approx,
    CASE
        WHEN sl.name IS NOT NULL
        THEN CAST(LOGINPROPERTY(sl.name, 'IsLocked')       AS BIT)
        ELSE NULL
    END                                                             AS is_currently_locked,
    CASE
        WHEN sl.name IS NOT NULL
        THEN CAST(LOGINPROPERTY(sl.name, 'BadPasswordCount') AS INT)
        ELSE NULL
    END                                                             AS bad_password_count,
    CASE
        WHEN agg.failure_count >= 50
        THEN 'CRITICAL — ' + CAST(agg.failure_count AS VARCHAR) +
             ' failures in ring buffer; likely brute-force or application misconfiguration'
        WHEN agg.failure_count >= 10
        THEN 'WARN — repeated failures for login [' + ISNULL(agg.login_name, '(unknown)') + ']'
        ELSE 'INFO'
    END                                                             AS status
FROM aggregated              AS agg
CROSS JOIN sys.dm_os_sys_info AS si
LEFT JOIN sys.sql_logins      AS sl ON sl.name = agg.login_name
ORDER BY agg.failure_count DESC;
