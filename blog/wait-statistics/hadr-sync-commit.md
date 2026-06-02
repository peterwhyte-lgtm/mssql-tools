---
title: "HADR_SYNC_COMMIT Wait Type — SQL Server"
slug: sql-server-wait-statistics-hadr-sync-commit
series: wait-statistics
series_position: 12
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, availability-groups, hadr-sync-commit, ha, alwayson]
seo_keyphrase: SQL Server HADR_SYNC_COMMIT
seo_title: "SQL Server HADR_SYNC_COMMIT — AG Synchronous Commit Lag"
seo_description: HADR_SYNC_COMMIT appears when an AG primary waits for synchronous secondaries to confirm log hardening. Learn how to find the lagging replica and fix it. (154 chars)
screenshots_needed:
  - Get-WaitStatistics output showing HADR_SYNC_COMMIT in top wait types on an AG primary
  - sys.dm_hadr_database_replica_states output showing log_send_queue_size and redo_queue_size for each secondary
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# HADR_SYNC_COMMIT — AG Synchronous Commit Lag

**Part of the [SQL Server Wait Statistics series](index.md)**

`HADR_SYNC_COMMIT` appears exclusively on Always On Availability Group primary replicas configured with at least one synchronous commit secondary. With synchronous commit, the primary cannot acknowledge a transaction commit to the application until the log records for that transaction have been written and hardened on *all* synchronous secondaries. `HADR_SYNC_COMMIT` is the time spent waiting for that confirmation.

If you don't use Always On Availability Groups — or all your AG secondaries are asynchronous — you will never see this wait type.

## Is this wait expected?

Some `HADR_SYNC_COMMIT` is the inherent cost of synchronous replication. Every committed transaction on a synchronous AG primary includes this wait as part of its commit path. The question is whether the wait is proportionate.

On a well-configured AG with both replicas in the same data centre on a fast network:
- `HADR_SYNC_COMMIT` should be low in absolute terms (sub-millisecond per commit)
- It may appear in your top 10 wait types but with small `avg_wait_ms`
- That's normal

It's a problem when:
- `avg_wait_ms` is elevated (above 2–5ms per commit consistently)
- It's your #1 or #2 wait type with a large `pct_total_wait`
- Application latency for write operations is noticeably higher than expected
- Users report slow response on insert/update/delete operations despite good hardware

## What the commit path looks like

Understanding the flow helps locate where the lag is:

```
Application issues COMMIT
  → Primary writes log records to log buffer  (WRITELOG wait — primary log disk)
  → Primary sends log block to secondary       (network)
  → Secondary receives and writes to log disk  (secondary log disk)
  → Secondary sends acknowledgement back       (network)
  → Primary receives ack                       (HADR_SYNC_COMMIT wait ends)
  → Application receives COMMIT confirmation
```

Any bottleneck in this chain increases `HADR_SYNC_COMMIT` on the primary.

## Root causes

**Network latency between primary and secondary** — the single most common cause. Every commit round-trip includes two network hops (send + ack). A 5ms network round-trip time means every commit takes at least 5ms of `HADR_SYNC_COMMIT` wait, regardless of how fast the disks are. Secondaries in remote data centres, connected via WAN or VPN, will always produce higher `HADR_SYNC_COMMIT` than co-located secondaries.

**Slow secondary log disk** — the secondary must write incoming log records to its own log file before acknowledging. If the secondary's log disk is slow (different storage tier, shared storage, spinning disk), the ack takes longer. This is separate from the primary's log disk — you can have fast primary storage and slow secondary storage.

**Secondary under CPU or I/O load** — a secondary that's busy serving read traffic (a readable secondary) or running other workloads (DBCC, backups, indexing) may have delayed redo and delayed log hardening. Under heavy load, log hardening can queue behind other I/O.

**Log block size and commit frequency** — very high-frequency, small transactions generate many small log blocks, each requiring a round-trip. Batching commits (fewer, larger transactions) reduces the number of round-trips even if total log volume is similar.

**Multiple synchronous secondaries** — the primary waits for *all* synchronous secondaries to acknowledge. If you have two synchronous secondaries and one is slow, the primary waits for the slower one every time.

## How to diagnose it

**Find the lagging replica:**

```sql
SELECT
    ar.replica_server_name,
    ar.availability_mode_desc,
    drs.synchronization_state_desc,
    drs.log_send_queue_size         AS send_queue_kb,
    drs.log_send_rate               AS send_rate_kbps,
    drs.redo_queue_size             AS redo_queue_kb,
    drs.redo_rate                   AS redo_rate_kbps,
    drs.last_sent_time,
    drs.last_received_time,
    drs.last_hardened_time,
    drs.last_redone_time,
    DATEDIFF(ms, drs.last_hardened_time, GETDATE()) AS ms_since_last_hardened
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar
    ON ar.replica_id = drs.replica_id
WHERE drs.is_local = 0  -- secondary replicas only
ORDER BY drs.log_send_queue_size DESC;
```

Key columns:
- `send_queue_kb > 0` — primary has log that hasn't been sent to the secondary yet. Network or secondary receive backlog.
- `redo_queue_kb > 0` — secondary has received log but hasn't hardened it yet. Secondary I/O is the bottleneck.
- `ms_since_last_hardened` growing over time — the secondary is falling behind on hardening.

**Check network round-trip time between primary and secondary:**

On the primary, ping the secondary server and measure the round-trip time. For synchronous commit, network latency directly adds to `HADR_SYNC_COMMIT` wait time. A 10ms ping means a minimum of 10ms per commit.

**Check secondary log disk write latency:**

Run the I/O stats query on the secondary:

```sql
-- Run this on the SECONDARY
SELECT
    DB_NAME(vfs.database_id)    AS database_name,
    mf.type_desc,
    mf.physical_name,
    CASE WHEN vfs.num_of_writes > 0
         THEN vfs.io_stall_write / vfs.num_of_writes ELSE 0 END AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
    ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
WHERE mf.type_desc = 'LOG'
ORDER BY avg_write_ms DESC;
```

High `avg_write_ms` on the secondary confirms the secondary log disk is the bottleneck.

**Check if this is a commit frequency problem:**

```sql
-- How many transactions per second is the primary doing?
SELECT
    cntr_value                  AS transactions_per_sec
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Transactions/sec'
  AND instance_name = '_Total';
```

Very high TPS with small transactions generates many round-trips. Batching reduces them.

## What to do

**If it's a network latency problem:**
- Co-locate synchronous secondaries — same data centre, same network segment, same rack if possible
- For secondaries that must be remote (DR in a different city): evaluate whether asynchronous commit is acceptable for that replica. Asynchronous commit eliminates `HADR_SYNC_COMMIT` for that replica entirely, at the cost of potential data loss on failover (RPO > 0). You can have one synchronous secondary local and one asynchronous secondary remote.

```sql
ALTER AVAILABILITY GROUP [YourAG]
MODIFY REPLICA ON 'RemoteServer'
WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
```

**If it's a slow secondary log disk:**
- Move the secondary log file to faster storage — ideally matching the primary's storage tier
- Ensure the secondary log disk isn't shared with other high-I/O workloads

**If the secondary is a readable secondary under load:**
- Review the read workload going to the secondary — heavy reporting queries during peak hours can degrade secondary I/O and redo performance
- Consider Resource Governor on the secondary to limit read workload resource consumption
- Schedule heavy reports for off-peak hours

**If it's commit frequency:**
- Batch transactions where the application allows — reduce the number of individual commits
- Review application code for row-by-row commit loops

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script; HADR_SYNC_COMMIT appears only on AG primaries
- [`WRITELOG`](writelog.md) — often elevated alongside HADR_SYNC_COMMIT; the primary log path is a related bottleneck

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server HADR_SYNC_COMMIT

**Meta description** (154 chars — target 150–160):  
HADR_SYNC_COMMIT appears when an AG primary waits for synchronous secondaries to confirm log hardening. Learn how to find the lagging replica and fix it.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `hadr-sync-commit-wait-stats.png` | SQL Server wait statistics on an AG primary showing HADR_SYNC_COMMIT in top wait types | HADR_SYNC_COMMIT in wait stats |
| `hadr-sync-commit-replica-states.png` | sys.dm_hadr_database_replica_states showing log_send_queue_size and last_hardened_time for two replicas | AG replica lag metrics |
