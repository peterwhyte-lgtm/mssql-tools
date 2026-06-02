---
title: "Script: Finding SQL Server Deadlocks from the System Health Session"
slug: sql-server-deadlock-analysis
published: 
published_url: 
status: draft
category: performance
tags: [deadlocks, locking, blocking, xevents, system-health, performance]
scripts:
  - sql/performance/Get-DeadlockSummary.sql
  - powershell/reporting/Get-DeadlockSummary.ps1
seo_keyphrase: SQL Server deadlocks
seo_title: "SQL Server Deadlocks — Finding and Reading Deadlock Graphs"
seo_description: SQL Server records deadlocks automatically in the system_health Extended Events session. Learn how to read the deadlock graph and find the statements involved. (157 chars)
screenshots_needed:
  - Get-DeadlockSummary output showing event_timestamp and deadlock_graph columns with XML results
  - SSMS deadlock graph viewer showing the graphical deadlock diagram with victim and winner highlighted
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Finding SQL Server Deadlocks from the System Health Session

A deadlock happens when two sessions each hold a lock the other needs. Session A holds Lock 1 and wants Lock 2. Session B holds Lock 2 and wants Lock 1. Neither can proceed. SQL Server detects this cycle within a few seconds, picks one session as the victim (typically the cheaper one to roll back), kills its transaction, and lets the other proceed.

The victim gets error 1205: "Transaction (Process ID N) was deadlocked on lock resources with another process and has been chosen as the deadlock victim."

Applications either retry the transaction or surface this as an error to the user. If deadlocks happen regularly, it's a real problem that needs a real fix — usually index changes, transaction order changes, or isolation level changes.

## The problem

Before Extended Events, diagnosing deadlocks required enabling trace flag 1222 or 1204, or setting up a SQL Server Profiler trace. Both required advance knowledge and active configuration.

Since SQL Server 2012, the `system_health` Extended Events session runs automatically and captures every deadlock event, including the full deadlock graph XML, without any configuration. The data is in the ring buffer (recent events, typically 30–60 minutes) and in the `.xel` files on disk (longer history, typically days).

## The script

```sql
WITH ring_buffer AS (
    SELECT
        CAST(target_data AS XML) AS ring_xml
    FROM sys.dm_xe_session_targets AS t
    INNER JOIN sys.dm_xe_sessions   AS s ON t.event_session_address = s.address
    WHERE s.name        = 'system_health'
      AND t.target_name = 'ring_buffer'
),
deadlock_nodes AS (
    SELECT
        e.x.value('@timestamp', 'datetime2')             AS event_timestamp,
        e.x.query('data[@name="xml_report"]/value')      AS deadlock_graph
    FROM ring_buffer
    CROSS APPLY ring_xml.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS e(x)
)
SELECT TOP 50
    event_timestamp,
    deadlock_graph
FROM deadlock_nodes
ORDER BY event_timestamp DESC;
```

## How to run it from the repo

```powershell
# Recent deadlocks from the ring buffer
.\run.ps1 Get-DeadlockSummary

# Save to CSV — note: the deadlock_graph XML column is best reviewed in SSMS
.\run.ps1 Get-DeadlockSummary -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `event_timestamp` | When the deadlock was detected and resolved. UTC timezone. |
| `deadlock_graph` | The full deadlock graph XML. In SSMS, right-click the cell value and choose "Save Results As..." to save the XML, then open it with the `.xdl` extension — SSMS will render it as a graphical deadlock diagram. |

## Reading the deadlock graph

The deadlock graph XML contains everything about the deadlock:

- Which sessions were involved
- What statement each was executing
- What locks each held
- What locks each was waiting for
- Which session was chosen as the victim (marked with a skull icon in the graphical view)

**To open the graphical deadlock diagram in SSMS:**

1. Run `Get-DeadlockSummary` in SSMS
2. Right-click the `deadlock_graph` cell for the deadlock you want to investigate
3. Select "Save Results As..."
4. Save with the extension `.xdl` (not `.xml`)
5. Open the saved file in SSMS — it will render as the graphical deadlock viewer

The graphical view shows:
- **Ovals** — the processes (sessions) involved
- **Rectangles** — the resources (locks) being contested
- **Blue arrows** — "I'm waiting for this lock"
- **Black arrows** — "I hold this lock"
- **Skull icon** — the deadlock victim (the session that was rolled back)

**Reading the XML directly** — if you prefer the raw XML, the key elements are:

```xml
<deadlock>
  <victim-list>
    <victimProcess id="process..." />   <!-- This session was killed -->
  </victim-list>
  <process-list>
    <process id="process..." spid="..." inputbuf="SELECT ...">
      <!-- The statement the session was running -->
    </process>
    <process id="process..." spid="..." inputbuf="UPDATE ...">
      <!-- The other session -->
    </process>
  </process-list>
  <resource-list>
    <!-- What was being locked and by whom -->
  </resource-list>
</deadlock>
```

The `inputbuf` attribute shows the SQL statement (or stored procedure call) each process was executing.

## Ring buffer vs. .xel file history

**Ring buffer** (what the script reads) — typically holds the last 30–60 minutes of system_health events. On busy servers with many deadlocks, it may be shorter. On quiet servers, it holds more.

**For longer history**, read the system_health `.xel` files directly in SSMS:

1. In SSMS, go to **File → Open → File...**
2. Navigate to the SQL Server LOG folder (typically `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Log\` or similar)
3. Open any `system_health_N.xel` file
4. The Extended Events viewer opens — filter for `xml_deadlock_report` events

Alternatively, query the files using `sys.fn_xe_file_target_read_file`:

```sql
SELECT
    object_name,
    CAST(event_data AS XML) AS event_xml,
    timestamp_utc
FROM sys.fn_xe_file_target_read_file(
    'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Log\system_health*.xel',
    NULL, NULL, NULL
)
WHERE object_name = 'xml_deadlock_report'
ORDER BY timestamp_utc DESC;
```

Adjust the path to match your instance's LOG folder location.

## What causes deadlocks

**The most common pattern: reader-writer deadlock**

Session A: reads Row 1, then tries to update Row 2  
Session B: reads Row 2, then tries to update Row 1

Both acquire shared locks when reading. Both try to upgrade to exclusive locks when updating. The upgrade requests block each other. Deadlock.

**Fix:** Enable Read Committed Snapshot Isolation (RCSI). Readers no longer take shared locks — they read from the version store instead. Reader-writer deadlocks disappear.

```sql
ALTER DATABASE [YourDatabase] SET READ_COMMITTED_SNAPSHOT ON;
```

**The second most common pattern: access order deadlock**

Two transactions update the same rows in different orders. Session A: updates Customer first, then Order. Session B: updates Order first, then Customer. If they interleave, each holds a lock the other needs.

**Fix:** Enforce a consistent lock acquisition order across all transactions that touch the same tables. Update Customer before Order everywhere — both transactions will queue at the same lock, not deadlock.

**Missing indexes**

A table scan acquires many more locks than a seek. Missing indexes can turn a 10-row operation into a full table scan that locks every row, vastly increasing the chance of deadlock with concurrent operations.

**Fix:** Add the missing index to reduce the lock footprint.

## What to do when deadlocks recur

1. Capture several deadlock graphs from the same recurring deadlock
2. Identify the two statements involved — look at `inputbuf` in the XML
3. Identify the locked resource — look at the resource-list
4. Determine whether it's a reader-writer pattern (→ RCSI) or an access-order pattern (→ consistent ordering) or a scan vs. seek pattern (→ missing index)
5. Test the fix in a non-production environment using the lab blocking script:

```powershell
.\run.ps1 Create-BlockingScenario
```

## Related scripts

- [`Get-BlockingSessions`](../blocking-sessions/index.md) — blocking is related but different; blocked sessions wait, deadlock victims get killed
- [`Get-WaitStatistics`](../wait-statistics/index.md) — `LCK_M_X` high in wait stats means blocking is frequent; frequent deadlocks often accompany this
- [`Get-MissingIndexes`](../missing-indexes/index.md) — missing indexes contribute to deadlocks by expanding lock footprint

## Get the scripts

The full script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-DeadlockSummary.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-DeadlockSummary.sql)
- [`powershell/reporting/Get-DeadlockSummary.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-DeadlockSummary.ps1)

---

## SEO

**Focus keyphrase:** SQL Server deadlocks

**Meta description** (157 chars — target 150–160):  
SQL Server records deadlocks automatically in the system_health Extended Events session. Learn how to read the deadlock graph and find the statements involved.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `deadlock-summary-output.png` | Get-DeadlockSummary output showing event_timestamp column and deadlock_graph XML cell value in SSMS results grid | Deadlock summary from ring buffer |
| `deadlock-graph-viewer.png` | SSMS graphical deadlock diagram showing two processes as ovals, locked resource as rectangle, and skull icon on victim | SSMS deadlock graph viewer |
