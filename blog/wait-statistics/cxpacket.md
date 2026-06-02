---
title: "CXPACKET and CXCONSUMER Wait Types — SQL Server"
slug: sql-server-wait-statistics-cxpacket-cxconsumer
series: wait-statistics
series_position: 4
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, parallelism, cxpacket, cxconsumer, maxdop]
seo_keyphrase: SQL Server CXPACKET wait
seo_title: "SQL Server CXPACKET and CXCONSUMER — Parallelism Waits Explained"
seo_description: CXPACKET and CXCONSUMER waits mean queries are running in parallel. Learn when this is normal, when it's a problem, and how MAXDOP settings control it. (152 chars)
screenshots_needed:
  - Get-WaitStatistics output showing CXPACKET and CXCONSUMER both in the top wait types
  - sys.configurations output showing max degree of parallelism and cost threshold for parallelism values
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# CXPACKET and CXCONSUMER — Parallelism Coordination Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

`CXPACKET` and `CXCONSUMER` appear whenever SQL Server runs a query using parallelism. They are the coordination overhead between parallel worker threads — not actual resource waits.

- **`CXPACKET`** — the thread that produces rows is waiting for a consumer thread to be ready to receive them. Or the coordinator thread is waiting for all parallel workers to finish their portions.
- **`CXCONSUMER`** — (added in SQL Server 2016 SP2 / 2017 CU3) a consuming thread is waiting for rows from the producer. Previously this was lumped into CXPACKET.

They almost always appear together. If you're on SQL Server 2016 or older, you'll only see CXPACKET.

## Is this wait expected?

Yes — they will appear on any server that runs parallel queries. Some level of CXPACKET/CXCONSUMER is completely normal and indicates SQL Server is using parallelism productively.

It becomes a signal worth investigating when:
- CXPACKET is your #1 wait type by a wide margin, especially on an OLTP server
- OLTP queries that should be fast (< 100ms) are running in parallel unnecessarily
- You're seeing high `avg_wait_ms` for CXPACKET (indicates threads are seriously out of sync)
- Users complain about slow ad-hoc queries that aren't returning large data sets

## When to ignore it

**Analytics and reporting workloads** — parallel queries are beneficial for large aggregations, sorts, and scans. `CXPACKET` being high on a reporting server is expected and healthy.

**Nightly batch jobs** — ETL, index rebuilds, statistics updates, and DBCC CHECKDB all benefit from parallelism. Ignore CXPACKET during maintenance windows.

**Any server with moderate CXPACKET alongside other waits** — if CXPACKET is 10–15% of total waits and other waits are present, it's just background parallelism coordination. Only chase it when it's dominant.

## Root causes

**Cost threshold for parallelism set too low** — the default of 5 means any query estimated to cost more than 5 "units" goes parallel. On modern hardware this threshold is hit by trivial queries. Raising it to 25–50 eliminates unnecessary parallelism for short OLTP queries without affecting large analytical queries.

**MAXDOP set too high** — if `max degree of parallelism` is set to the CPU count (or left at 0 meaning unlimited), every parallel query spawns many threads. More threads = more coordination overhead = more CXPACKET. A common recommendation is to set MAXDOP to 4–8 for OLTP, or to the number of logical cores per NUMA node, whichever is lower.

**Skewed parallelism (one slow thread)** — parallel query plans divide work across threads. If the work is unevenly distributed (one thread gets 90% of the rows), the fast threads finish and sit in CXPACKET waiting for the slow thread. This shows up as high `max_wait_time_ms` for CXPACKET. Often caused by poor statistics or uneven data distribution.

**Missing indexes triggering large parallel scans** — a query that should be a fast index seek might fall back to a parallel table scan if the index doesn't exist or the optimiser underestimates selectivity. The scan runs in parallel, generating CXPACKET.

## How to diagnose it

**Check current MAXDOP and cost threshold settings:**

```sql
SELECT name, value_in_use, description
FROM sys.configurations
WHERE name IN (
    'max degree of parallelism',
    'cost threshold for parallelism'
);
```

**Check if specific queries are driving CXPACKET:**

```sql
SELECT TOP 20
    qs.total_elapsed_time / qs.execution_count  AS avg_elapsed_us,
    qs.max_degree_of_parallelism,
    qs.execution_count,
    SUBSTRING(qt.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(qt.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qs.max_degree_of_parallelism > 1
ORDER BY qs.total_elapsed_time DESC;
```

Queries with high `max_degree_of_parallelism` that are supposed to be fast OLTP queries are your targets.

**Spot skewed parallelism** — look for queries where the actual execution plan shows very uneven row counts across parallel threads. In SSMS: run the query with "Include Actual Execution Plan", then look at the parallel operators — hover over the arrows to see per-thread row counts.

## What to do

**Raise cost threshold for parallelism** — this is almost always the first fix:

```sql
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
```

A value of 25–50 eliminates most unnecessary parallelism on OLTP workloads without affecting large analytical queries. The exact value depends on your workload — start at 25 and monitor.

**Set MAXDOP appropriately:**

```sql
EXEC sp_configure 'max degree of parallelism', 4;
RECONFIGURE;
```

For mixed OLTP/reporting workloads, MAXDOP 4–8 is a common starting point. For a NUMA system, set MAXDOP to the number of logical cores per NUMA node.

**For Resource Governor (SQL Server Enterprise):**
- Set different MAX_DOP per workload group — restrict OLTP queries to lower DOP while allowing reports to use more

**For a specific bad query while you investigate:**
```sql
SELECT ... FROM ... WHERE ... OPTION (MAXDOP 1);
```

**Address skewed parallelism:**
- Update statistics on the tables involved
- Add missing indexes to avoid large scans
- Review data distribution — very skewed distributions may need filtered indexes

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script
- [`Get-MissingIndexes`](../missing-indexes/index.md) — missing indexes often cause parallel scans
- [`Get-MaxdopConfiguration`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/inventory/Get-MaxdopConfiguration.ps1) — check current MAXDOP settings across instances

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server CXPACKET wait

**Meta description** (152 chars — target 150–160):  
CXPACKET and CXCONSUMER waits mean queries are running in parallel. Learn when this is normal, when it's a problem, and how MAXDOP settings control it.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `cxpacket-wait-stats.png` | SQL Server wait statistics output showing CXPACKET and CXCONSUMER both in top five wait types | CXPACKET and CXCONSUMER in wait stats |
| `cxpacket-config.png` | sys.configurations showing max degree of parallelism set to 8 and cost threshold for parallelism at 5 | MAXDOP and cost threshold settings |
