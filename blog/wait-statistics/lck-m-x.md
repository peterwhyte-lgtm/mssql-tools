---
title: "LCK_M_X, LCK_M_S, and LCK_M_U Wait Types — SQL Server"
slug: sql-server-wait-statistics-lock-waits
series: wait-statistics
series_position: 6
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, locking, blocking, lck-m-x, lck-m-s]
seo_keyphrase: SQL Server LCK_M_X wait
seo_title: "SQL Server LCK_M_X, LCK_M_S, LCK_M_U — Lock Wait Types"
seo_description: SQL Server LCK_M_X and LCK_M_S waits mean queries are waiting for locks held by other sessions. Learn what's causing blocking and how to stop it. (149 chars)
screenshots_needed:
  - Get-WaitStatistics output showing LCK_M_X or LCK_M_S as a prominent wait type
  - Get-BlockingSessions output showing the head blocker and blocked sessions chain
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# LCK_M_X, LCK_M_S, LCK_M_U — Lock Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

These wait types mean queries are blocked waiting for locks held by other sessions:

- **`LCK_M_X`** — waiting for an **exclusive** lock. Needed before any INSERT, UPDATE, or DELETE on a row. If another session holds a shared, update, or exclusive lock on the same row or page, this request must wait.
- **`LCK_M_S`** — waiting for a **shared** lock. Needed for reads under the default isolation level (READ COMMITTED without RCSI). If a writer holds an exclusive lock, readers wait here.
- **`LCK_M_U`** — waiting for an **update** lock. Used during the read phase of an UPDATE — SQL Server takes a U lock before escalating to X. Contention here means multiple sessions are trying to update the same rows.

High values for any of these mean blocking is happening regularly and accumulating significant wait time.

## Is this wait expected?

Small amounts of locking are inherent in transactional systems. Under READ COMMITTED (the default), shared locks are held briefly and released as rows are read — this generates almost no `LCK_M_S`. `LCK_M_X` appears when writers compete for the same rows.

It's a problem when:
- `LCK_M_X` or `LCK_M_S` is in your top three wait types
- `avg_wait_ms` is in the seconds, not milliseconds
- Users are reporting timeouts or sluggish response during peak hours
- You see connection pooling saturation — queries piling up waiting for locks

## When to ignore it

**Short, infrequent lock waits** — a small amount of `LCK_M_X` from occasional row-level conflicts is normal. Look at `avg_wait_ms` — if average waits are < 10ms, it's not causing pain.

**Batch maintenance windows** — large UPDATE or DELETE operations will cause temporary locking. Expected if it's contained to a known maintenance window.

## What LCK_M_X vs LCK_M_S tells you

**LCK_M_X dominant** — writers are blocking other writers. Two sessions are trying to modify the same rows simultaneously. This happens with hot rows — a single row that many sessions update (counters, queues, order IDs).

**LCK_M_S dominant** — writers are blocking readers. Under READ COMMITTED (without RCSI), a reader takes a shared lock that conflicts with a writer's exclusive lock. This is the most common blocking pattern. The fix is usually enabling Read Committed Snapshot Isolation (RCSI).

**LCK_M_U dominant** — update contention. Multiple sessions are running UPDATEs that read-then-modify the same row range. U locks prevent the "lost update" pattern where two sessions read the same value, modify it, and write conflicting results.

## Root causes

**Long-running transactions holding locks** — the most common cause. A transaction begins, acquires locks, then does something slow (network call, user interaction, long calculation, another query) while holding those locks. Everything else that needs those rows waits.

**Missing indexes causing lock escalation** — a query that should seek to a few rows via an index instead scans a large range, taking locks on every row it touches. A missing index turns a 10-row lock into a 10,000-row lock.

**Row-level vs page-level vs table-level escalation** — SQL Server starts with row locks but escalates to page locks and then table locks when it acquires too many row locks (default threshold: 5000 locks per table). A full table lock blocks everything.

**Incorrect isolation level** — using SERIALIZABLE or REPEATABLE READ unnecessarily. These hold shared locks for the duration of the transaction, not just until the row is read. Queries that don't need this guarantee should use READ COMMITTED.

**Hot rows** — a single row being updated by many concurrent sessions. Queuing mechanisms, counter tables, and order sequence generators are common examples.

## How to diagnose it

Use the blocking scripts from this repo to investigate live:

```powershell
# Quick summary — is blocking happening, who is the head blocker?
.\run.ps1 Get-BlockingSummary

# Full chain — every blocked session and what's blocking them
.\run.ps1 Get-BlockingSessions
```

**Identify the head blocker manually:**

```sql
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time / 1000.0            AS wait_sec,
    r.wait_resource,
    DB_NAME(r.database_id)          AS database_name,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1) AS blocked_statement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0
ORDER BY r.wait_time DESC;
```

Sessions with `blocking_session_id = 0` but with other sessions waiting on them are the head blockers. Look at what the head blocker is doing — is it idle in an open transaction?

**Check for open idle transactions:**

```sql
SELECT
    s.session_id,
    s.status,
    s.open_transaction_count,
    s.last_request_start_time,
    s.last_request_end_time,
    s.program_name,
    s.host_name
FROM sys.dm_exec_sessions s
WHERE s.open_transaction_count > 0
  AND s.status = 'sleeping'
ORDER BY s.last_request_end_time;
```

A sleeping session with an open transaction is the classic head blocker. The application opened a transaction, ran a query, and then paused (user think time, application processing) without committing.

## What to do

**Find and fix the head blocker first** — killing it buys time, but doesn't fix the root cause. Identify the application responsible (`program_name`, `host_name`) and the transaction pattern.

**Enable Read Committed Snapshot Isolation (RCSI)** — for `LCK_M_S` (reader blocked by writer), RCSI eliminates most reader/writer conflicts. Readers take no shared locks; they read from the version store instead. Enable per database:

```sql
ALTER DATABASE [YourDatabase] SET READ_COMMITTED_SNAPSHOT ON;
```

This requires no application changes, has no compatibility level requirement, but does increase tempdb usage (version store).

**Shorten transaction scope** — move logic outside BEGIN TRAN/COMMIT. Don't call external services, do expensive calculations, or wait for user input inside a transaction.

**Add missing indexes** — reduce lock duration by making queries faster, and reduce lock scope by turning scans into seeks.

**For hot rows** — avoid updating a single shared row from many sessions simultaneously. Common patterns:
- Sequence tables: use IDENTITY or sequences instead
- Counter tables: use `UPDATE ... WITH (ROWLOCK)` and avoid scanning
- Queue tables: use `READPAST` hint to skip locked rows

**For serializable-level blocking** — review whether SERIALIZABLE isolation is actually needed. Most OLTP workloads run fine on READ COMMITTED.

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script
- [`Get-BlockingSummary`](../blocking-sessions/index.md) — quick triage when blocking is happening
- [`Get-BlockingSessions`](../blocking-sessions/index.md) — full chain with blocked statements
- [`Get-BlockingChains`](../blocking-chains/index.md) — recursive chain analysis with execution plans

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server LCK_M_X wait

**Meta description** (149 chars — target 150–160):  
SQL Server LCK_M_X and LCK_M_S waits mean queries are waiting for locks held by other sessions. Learn what's causing blocking and how to stop it.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `lck-m-x-wait-stats.png` | SQL Server wait statistics showing LCK_M_X and LCK_M_S in top wait types with pct_total_wait | Lock waits in wait statistics |
| `lck-m-x-blocking-sessions.png` | Get-BlockingSessions output showing head blocker at depth 0 and blocked sessions at depth 1 and 2 | Blocking session chain output |
