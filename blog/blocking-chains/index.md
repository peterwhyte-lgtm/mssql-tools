---
title: "Script: SQL Server Blocking Chain Analysis with Execution Plans"
slug: sql-server-blocking-chains
published: 
published_url: 
status: draft
category: performance
tags: [blocking, locking, chains, deadlocks, performance]
scripts:
  - sql/performance/Get-BlockingChains.sql
  - sql/performance/Get-BlockingChainsWithPlan.sql
seo_keyphrase: SQL Server blocking chains
seo_title: "SQL Server Blocking Chain Analysis with Execution Plans"
seo_description: Trace SQL Server blocking chains to the root blocker using a recursive CTE. Includes the execution plan variant for identifying the exact statement causing the lock. (169 chars — trim before publishing)
screenshots_needed:
  - Get-BlockingChains output showing multi-level blocking chain with depth column (root at 0, blocked sessions at depth 1, 2+)
  - Get-BlockingChainsWithPlan output with execution plan XML visible, showing the locking statement
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Blocking Chain Analysis with Execution Plans

The [blocking sessions post](../blocking-sessions/index.md) covers the fast triage view — is there blocking right now, who is the head blocker, how long has it been going. This post covers the next step: the full chain analysis that shows every session at every depth of the blocking tree, plus the execution plan variant that shows the exact statement holding the lock.

When blocking is a recurring problem rather than a one-off, you need the chain. A head blocker at depth 0 blocking a session at depth 1 that is itself blocking three sessions at depth 2 is a very different problem from a simple two-session block. The recursive CTE approach maps the entire tree in a single result set, ordered by chain so you can read it like a hierarchy.

## The problem

Blocking chains with more than two levels are difficult to trace manually. `sys.dm_exec_requests.blocking_session_id` gives you one level — who is blocked by whom right now. To find the root of a deep chain, you'd have to follow `blocking_session_id` manually, hop by hop, until you reach a session with `blocking_session_id = 0`.

The chain script does that recursively and presents the entire tree in one result set. The execution plan variant adds the query plan for the blocking statement, so instead of just knowing *that* a session holds a lock, you can see *which specific operation* in the plan is holding it.

## The scripts

### Get-BlockingChains.sql — full recursive chain

```sql
WITH BlockingChain AS (
    -- Head blockers: not blocked themselves, but have someone waiting on them
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        r.status,
        r.command,
        r.database_id,
        r.sql_handle,
        r.statement_start_offset,
        r.statement_end_offset,
        0                                                   AS depth,
        CAST(r.session_id AS VARCHAR(4000))                 AS chain
    FROM sys.dm_exec_requests r
    WHERE r.blocking_session_id = 0
      AND EXISTS (
          SELECT 1 FROM sys.dm_exec_requests r2
          WHERE r2.blocking_session_id = r.session_id
      )

    UNION ALL

    -- Blocked sessions: joined back to their blocker
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        r.status,
        r.command,
        r.database_id,
        r.sql_handle,
        r.statement_start_offset,
        r.statement_end_offset,
        bc.depth + 1,
        bc.chain + ' → ' + CAST(r.session_id AS VARCHAR(10))
    FROM sys.dm_exec_requests r
    JOIN BlockingChain bc ON bc.session_id = r.blocking_session_id
)
SELECT
    bc.depth,
    bc.chain                            AS blocking_chain,
    bc.session_id,
    bc.blocking_session_id,
    bc.status,
    bc.wait_type,
    bc.wait_time / 1000.0               AS wait_sec,
    bc.wait_resource,
    DB_NAME(bc.database_id)             AS database_name,
    s.login_name,
    s.program_name,
    s.host_name,
    s.open_transaction_count,
    SUBSTRING(t.text,
        (bc.statement_start_offset / 2) + 1,
        ((CASE bc.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE bc.statement_end_offset END - bc.statement_start_offset) / 2) + 1
    )                                   AS current_statement
FROM BlockingChain bc
JOIN sys.dm_exec_sessions s ON s.session_id = bc.session_id
CROSS APPLY sys.dm_exec_sql_text(bc.sql_handle) t
ORDER BY bc.chain, bc.depth;
```

### Get-BlockingChainsWithPlan.sql — adds the execution plan

```sql
WITH BlockingChain AS (
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        r.status,
        r.database_id,
        r.sql_handle,
        r.plan_handle,
        r.statement_start_offset,
        r.statement_end_offset,
        0                                                   AS depth,
        CAST(r.session_id AS VARCHAR(4000))                 AS chain
    FROM sys.dm_exec_requests r
    WHERE r.blocking_session_id = 0
      AND EXISTS (SELECT 1 FROM sys.dm_exec_requests r2
                  WHERE r2.blocking_session_id = r.session_id)

    UNION ALL

    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        r.status,
        r.database_id,
        r.sql_handle,
        r.plan_handle,
        r.statement_start_offset,
        r.statement_end_offset,
        bc.depth + 1,
        bc.chain + ' → ' + CAST(r.session_id AS VARCHAR(10))
    FROM sys.dm_exec_requests r
    JOIN BlockingChain bc ON bc.session_id = r.blocking_session_id
)
SELECT
    bc.depth,
    bc.chain                            AS blocking_chain,
    bc.session_id,
    bc.blocking_session_id,
    bc.status,
    bc.wait_type,
    bc.wait_time / 1000.0               AS wait_sec,
    bc.wait_resource,
    DB_NAME(bc.database_id)             AS database_name,
    s.login_name,
    s.program_name,
    SUBSTRING(t.text,
        (bc.statement_start_offset / 2) + 1,
        ((CASE bc.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE bc.statement_end_offset END - bc.statement_start_offset) / 2) + 1
    )                                   AS current_statement,
    qp.query_plan                       AS execution_plan_xml
FROM BlockingChain bc
JOIN sys.dm_exec_sessions s   ON s.session_id = bc.session_id
CROSS APPLY sys.dm_exec_sql_text(bc.sql_handle)  t
CROSS APPLY sys.dm_exec_query_plan(bc.plan_handle) qp
ORDER BY bc.chain, bc.depth;
```

## How to run it from the repo

```powershell
# Full chain without plans — fast triage when blocking is active
.\run.ps1 Get-BlockingChains

# With execution plans — use when you need to see the locking statement
.\run.ps1 Get-BlockingChainsWithPlan

# Save to CSV for documentation
.\run.ps1 Get-BlockingChains -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `depth` | Position in the blocking tree. 0 = head blocker. 1 = directly blocked by head blocker. 2 = blocked by depth 1, etc. |
| `blocking_chain` | The full chain path as session IDs, e.g. `55 → 67 → 82 → 89`. Read left to right — leftmost is the root. |
| `session_id` | The session on this row. |
| `blocking_session_id` | The session that this one is directly blocked by. |
| `wait_type` | The lock type being waited for. `LCK_M_X`, `LCK_M_S`, etc. |
| `wait_sec` | How long this session has been waiting. |
| `wait_resource` | The specific object being locked — database, object, and page/row identifiers. |
| `open_transaction_count` | Number of open transactions for this session. A head blocker at depth 0 with `open_transaction_count > 0` is holding a transaction open. |
| `current_statement` | The SQL statement currently executing or most recently executed. |
| `execution_plan_xml` | (Plan variant only) The execution plan — click the link in SSMS to open the graphical plan and see exactly which operator holds the lock. |

## What to look for

**The head blocker at depth 0** — this is your target. The session in the `blocking_chain` value with no `→` to its left is the root. Look at:
- Is its `status` = `sleeping`? If a sleeping session has `open_transaction_count > 0`, it finished its query but didn't commit. The application is holding a transaction open while doing something else. This is the most common pattern.
- What is its `current_statement`? If it's sleeping, this shows the last statement it ran before going idle.
- What is its `program_name`? This tells you which application owns the blocking session.

**Chain depth** — a chain of depth 3 or 4 means one blocker is causing a cascade. Kill the head blocker and all downstream sessions unblock simultaneously.

**Using the execution plan** — in the plan variant, click on the `execution_plan_xml` value in SSMS to open the graphical plan. Look for lock icons on operators — a Lock Wait symbol appears on operators that are waiting for or holding locks relevant to the blocking.

## Creating a blocking scenario for testing

The repo includes a lab script to generate controllable blocking for testing:

```powershell
# Create a test database and reproduce a blocking chain
.\run.ps1 Create-BlockingScenario

# Then run the chain scripts against it to see the output
.\run.ps1 Get-BlockingChains
```

This spins up a three-session blocking chain — head blocker → one direct block → two sessions blocked at depth 2 — so you can see the chain output with real data before using it in production.

## What to do

**Short term — stop the immediate bleeding:**

Find the head blocker (depth 0) and verify it's idle in a transaction:

```sql
SELECT session_id, status, open_transaction_count, last_request_end_time, program_name
FROM sys.dm_exec_sessions
WHERE session_id = [head_blocker_session_id];
```

If it's sleeping with an open transaction, kill it:

```sql
KILL [head_blocker_session_id];
```

This unblocks the entire chain immediately. Document what you killed (program, host, statement) for follow-up.

**Long term — fix the application pattern:**

The most common pattern behind a sleeping head blocker is an application that:
1. Opens a transaction
2. Runs a query (acquires locks)
3. Does something outside the transaction — calls an API, waits for user input, processes results
4. Eventually commits — or disconnects without committing

Fixes:
- Move external calls *outside* the transaction — open transaction, run query, commit, then call the API
- Set a connection timeout so sessions don't stay open indefinitely
- Review connection pooling — disconnecting without committing in a pooled connection returns a dirty connection to the pool

For persistent blocking from long-running but legitimate writes (e.g. a large batch update):
- Break the batch into smaller chunks that each commit quickly
- Enable Read Committed Snapshot Isolation (RCSI) to eliminate reader/writer blocking

## Related scripts

- [`Get-BlockingSummary`](../blocking-sessions/index.md) — fast triage: is blocking happening and who is the root?
- [`Get-BlockingSessions`](../blocking-sessions/index.md) — per-session detail without the recursive chain
- [`Get-WaitStatistics`](../wait-statistics/index.md) — if `LCK_M_X` or `LCK_M_S` is in the top waits, start here

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-BlockingChains.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-BlockingChains.sql)
- [`sql/performance/Get-BlockingChainsWithPlan.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-BlockingChainsWithPlan.sql)

---

## SEO

**Focus keyphrase:** SQL Server blocking chains

**Meta description** (169 chars — trim to 160 before publishing):  
Trace SQL Server blocking chains to the root blocker using a recursive CTE. Includes the execution plan variant for identifying the exact statement causing the lock.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `blocking-chains-output.png` | Get-BlockingChains output showing depth 0 head blocker and depth 1 and 2 blocked sessions with blocking_chain column | Blocking chain recursive output |
| `blocking-chains-plan-output.png` | Get-BlockingChainsWithPlan result with execution_plan_xml column showing a clickable plan link in SSMS | Blocking chain with execution plan |
