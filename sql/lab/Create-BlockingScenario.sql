/*
Script Name : Create-BlockingScenario
Category    : lab
Purpose     : Controlled blocking scenario for testing Get-BlockingChains, Get-BlockingSessions,
              and blocking analysis tools. Uses WAITFOR DELAY so the lock releases automatically —
              no manual ROLLBACK required.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Writes data
Impact      : Medium  *** DEV / TEST INSTANCES ONLY ***
Requires    : CREATE TABLE, INSERT, UPDATE, DROP TABLE
*/
-- SAFE:WritesData
-- IMPACT:Medium
-- LAB:DevOnly

/*
╔══════════════════════════════════════════════════════════════════╗
║  HOW TO RUN THIS DEMO                                            ║
║                                                                  ║
║  You need TWO SSMS windows connected to the same instance.      ║
║                                                                  ║
║  1. Run STEP 1 (Setup) in either window.                        ║
║                                                                  ║
║  2. Highlight STEP 2 only → run it in Window 1.                 ║
║     It holds a lock for 45 seconds then releases automatically. ║
║                                                                  ║
║  3. Immediately switch to Window 2.                             ║
║     Highlight STEP 3 only → run it. It will hang.              ║
║                                                                  ║
║  4. Run STEP 4 in any window to see the blocking chain.         ║
║                                                                  ║
║  5. Run STEP 5 to clean up after the demo.                      ║
╚══════════════════════════════════════════════════════════════════╝
*/


/* ================================================================
   STEP 1 — SETUP  (run once in either window)
   ================================================================ */

IF OBJECT_ID('dbo.lab_blocking_test', 'U') IS NOT NULL
    DROP TABLE dbo.lab_blocking_test;

CREATE TABLE dbo.lab_blocking_test (
    order_id   INT           NOT NULL CONSTRAINT PK_lab_blocking PRIMARY KEY CLUSTERED,
    customer   VARCHAR(50)   NOT NULL,
    status     VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    amount     DECIMAL(10,2) NOT NULL,
    updated_at DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);

INSERT INTO dbo.lab_blocking_test (order_id, customer, status, amount) VALUES
    (1, 'Acme Corp',   'PENDING', 1250.00),
    (2, 'Beta Ltd',    'PENDING',  750.00),
    (3, 'Gamma Inc',   'PENDING', 2100.00);

SELECT * FROM dbo.lab_blocking_test ORDER BY order_id;
-- Setup complete. All 3 rows visible.


/* ================================================================
   STEP 2 — WINDOW 1: THE BLOCKER
   Highlight from BEGIN TRANSACTION to the final SELECT and run.
   Holds an exclusive lock on order_id = 1 for 45 seconds,
   then commits automatically. You have 45 seconds to run Step 3.
   ================================================================ */

BEGIN TRANSACTION;

    UPDATE dbo.lab_blocking_test
    SET    status     = 'PROCESSING',
           updated_at = SYSDATETIME()
    WHERE  order_id   = 1;

    WAITFOR DELAY '00:00:45';  -- lock held for 45 seconds

COMMIT TRANSACTION;

SELECT order_id, status, updated_at
FROM   dbo.lab_blocking_test
WHERE  order_id = 1;
-- Shows PROCESSING after commit. Window 2 will have set it to SHIPPED.


/* ================================================================
   STEP 3 — WINDOW 2: THE BLOCKED QUERY
   Run in the second SSMS window WHILE Step 2 is running.
   This query will hang until Window 1's WAITFOR expires.
   ================================================================ */

UPDATE dbo.lab_blocking_test
SET    status     = 'SHIPPED',
       updated_at = SYSDATETIME()
WHERE  order_id   = 1;

SELECT order_id, status, updated_at
FROM   dbo.lab_blocking_test
WHERE  order_id = 1;
-- Shows SHIPPED once unblocked (Window 1 committed PROCESSING,
-- then this UPDATE overwrites it).


/* ================================================================
   STEP 4 — DETECT  (run in any window while Steps 2 and 3 are active)
   ================================================================ */

-- Quick blocking check
SELECT
    r.session_id                                        AS blocked_session,
    r.blocking_session_id                               AS blocking_session,
    r.wait_type,
    r.wait_time / 1000                                  AS wait_seconds,
    r.status,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
              WHEN -1 THEN DATALENGTH(t.text)
              ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1
    )                                                   AS blocked_statement,
    s.login_name,
    s.host_name,
    s.program_name
FROM       sys.dm_exec_requests      r
JOIN       sys.dm_exec_sessions      s  ON r.session_id       = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0
ORDER BY r.wait_time DESC;

-- Or use the repo scripts from PowerShell:
--   .\run.ps1 Get-BlockingChains     -- recursive CTE: full chain with depth and downstream waiters
--   .\run.ps1 Get-BlockingSessions   -- flat view: head blocker + all blocked sessions
--   .\run.ps1 Get-ActiveSessions     -- all sessions including open transactions


/* ================================================================
   STEP 5 — CLEANUP  (run after the demo)
   ================================================================ */

IF OBJECT_ID('dbo.lab_blocking_test', 'U') IS NOT NULL
    DROP TABLE dbo.lab_blocking_test;

SELECT OBJECT_ID('dbo.lab_blocking_test') AS should_be_null;
