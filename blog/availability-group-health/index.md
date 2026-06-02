---
title: "Script: SQL Server Availability Group Health and Latency Check"
slug: sql-server-availability-group-health
published: 
published_url: 
status: draft
category: monitoring
tags: [availability-groups, ha, dr, alwayson, replication, latency]
scripts:
  - sql/high-availability/Get-AvailabilityGroupReplicaState.sql
  - sql/high-availability/Get-AvailabilityGroupLatency.sql
  - powershell/high-availability/Get-AvailabilityGroupReplicaState.ps1
  - powershell/high-availability/Get-AvailabilityGroupLatency.ps1
seo_keyphrase: SQL Server availability group health
seo_title: "SQL Server Availability Group Health and Latency Monitoring"
seo_description: Monitor SQL Server Always On Availability Group replica state, connection health, and synchronization lag with two scripts that cover both replica and database-level status. (173 chars — trim)
screenshots_needed:
  - Get-AvailabilityGroupReplicaState output showing ag_name, replica_server_name, role_desc, connected_state_desc, and synchronization_health_desc columns
  - Get-AvailabilityGroupLatency output showing log_send_queue_size and redo_queue_size per database per replica
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Availability Group Health and Latency Check

Always On Availability Groups are SQL Server's primary high availability and disaster recovery technology. They replicate transaction log records from a primary replica to one or more secondary replicas, keeping the secondaries in sync. When something goes wrong — network partition, secondary disk failure, excessive secondary load — the AG falls behind, and failover readiness is compromised.

Two scripts provide the full picture: replica-level health (is each replica connected and in a healthy synchronization state?) and database-level latency (how far behind is each database on each replica, and how fast is it catching up?).

## The scripts

### Get-AvailabilityGroupReplicaState.sql — replica connection and sync health

```sql
SELECT
    ag.name                         AS ag_name,
    ar.replica_server_name,
    ar.role_desc,
    ar.operational_state_desc,
    ar.connected_state_desc,
    ar.synchronization_health_desc,
    ar.synchronization_state_desc,
    ar.last_connect_error_number,
    ar.last_connect_error_description,
    ar.last_connect_error_timestamp
FROM sys.availability_replicas AS ar
JOIN sys.availability_groups   AS ag ON ar.group_id = ag.group_id
ORDER BY ag.name, ar.replica_server_name;
```

### Get-AvailabilityGroupLatency.sql — database-level sync queue and rates

```sql
SELECT
    ag.name                         AS ag_name,
    ar.replica_server_name,
    ar.role_desc,
    DB_NAME(drs.database_id)        AS database_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.log_send_queue_size,
    drs.log_send_rate,
    drs.redo_queue_size,
    drs.redo_rate
FROM sys.dm_hadr_database_replica_states AS drs
INNER JOIN sys.availability_replicas AS ar ON drs.replica_id = ar.replica_id
INNER JOIN sys.availability_groups   AS ag ON ar.group_id = ag.group_id
ORDER BY ag.name, database_name, ar.replica_server_name;
```

## How to run it from the repo

```powershell
# Replica-level state and health
.\run.ps1 Get-AvailabilityGroupReplicaState

# Database-level latency and queue sizes
.\run.ps1 Get-AvailabilityGroupLatency

# Save both for incident documentation
.\run.ps1 Get-AvailabilityGroupReplicaState -OutputFormat Csv
.\run.ps1 Get-AvailabilityGroupLatency -OutputFormat Csv
```

Note: both scripts check `SERVERPROPERTY('IsHadrEnabled')` and return an informational message rather than an error if Always On is not enabled on this instance.

## Reading the output — Get-AvailabilityGroupReplicaState

| Column | What it means |
|--------|---------------|
| `ag_name` | Name of the availability group. |
| `replica_server_name` | The server name of this replica. |
| `role_desc` | `PRIMARY` or `SECONDARY`. Shows the current role, which changes after a failover. |
| `operational_state_desc` | `ONLINE` is normal. `OFFLINE`, `FAILED`, or `PENDING_FAILOVER` need investigation. |
| `connected_state_desc` | `CONNECTED` is normal. `DISCONNECTED` means the replica cannot be reached from the primary. |
| `synchronization_health_desc` | `HEALTHY` is normal. `PARTIALLY_HEALTHY` means at least one database is not synchronising. `NOT_HEALTHY` means no databases are synchronising — the replica is effectively disconnected from replication. |
| `synchronization_state_desc` | `SYNCHRONIZED` (for synchronous mode) or `SYNCHRONIZING` (for asynchronous mode, or synchronous mode catching up). A synchronous replica stuck in `SYNCHRONIZING` is not failover-ready. |
| `last_connect_error_number` / `_description` / `_timestamp` | If the replica is disconnected, these show the last connection error. Useful for diagnosing network or authentication issues. |

## Reading the output — Get-AvailabilityGroupLatency

| Column | What it means |
|--------|---------------|
| `replica_server_name` | The replica — run from the primary, secondaries show their lag. |
| `database_name` | Each AG database is reported separately. |
| `synchronization_state_desc` | `SYNCHRONIZED` (caught up, synchronous mode) or `SYNCHRONIZING` (catching up, or asynchronous mode). |
| `last_hardened_time` | When the secondary last confirmed log records were hardened to its log disk. The delta between this and the primary's log position represents the secondary's lag. |
| `last_redone_time` | When the secondary last applied (redid) log records to its data files. The secondary may have hardened log records before it finishes applying them to pages. |
| `log_send_queue_size` | KB of log records generated on the primary that haven't been sent to this secondary yet. **Non-zero means the secondary is falling behind on receiving log.** Zero is healthy. |
| `log_send_rate` | KB per second the primary is sending to this secondary. |
| `redo_queue_size` | KB of log records received by the secondary but not yet applied to the data files. Non-zero means the secondary is applying log slower than it receives it. |
| `redo_rate` | KB per second the secondary is applying log. |

## What to look for

**`connected_state_desc = DISCONNECTED`** — the most critical finding. The primary has lost contact with a secondary. Until reconnected, the secondary is not receiving new log records. For a synchronous replica, this blocks commits on the primary (HADR_SYNC_COMMIT waits). For an async replica, the primary continues but the secondary falls further behind.

**`synchronization_health_desc = NOT_HEALTHY`** — one or more databases in the AG are not synchronising. This replica is not a valid failover target in its current state.

**`log_send_queue_size` growing** — the secondary is not receiving log fast enough. Usually a network bandwidth or latency issue. Check network throughput between primary and secondary.

**`redo_queue_size` growing** — the secondary is receiving log but not applying it fast enough. Usually a secondary disk performance issue, or the secondary is under heavy load (read workloads on a readable secondary). Check `avg_write_ms` on the secondary log file:

```sql
-- Run this on the SECONDARY
SELECT DB_NAME(database_id) AS database_name,
       io_stall_write / NULLIF(num_of_writes, 0) AS avg_log_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
WHERE mf.type_desc = 'LOG'
ORDER BY avg_log_write_ms DESC;
```

**`log_send_queue_size = 0` and `redo_queue_size = 0`** — the secondary is fully caught up. This is the healthy state for both synchronous and asynchronous replicas during normal operation.

## Estimating how long to catch up

If `redo_queue_size > 0` and `redo_rate > 0`:

```
estimated_catch_up_seconds = redo_queue_size / redo_rate
```

If `redo_rate = 0` (redo is stopped or paused), the secondary won't catch up until redo resumes.

## When a secondary falls badly behind

Asynchronous secondaries can fall arbitrarily far behind without affecting the primary. Synchronous secondaries either prevent falls (by blocking primary commits) or automatically fail over to asynchronous mode under prolonged disconnection (depending on the AG configuration).

If a secondary has fallen very far behind and must catch up:

1. **Verify the cause first** — network, disk, or load?
2. **Let it catch up naturally** — if the cause is resolved, the secondary will redo at the rate its disk allows. Don't try to accelerate by manipulating the AG.
3. **Consider a reseed** — if the secondary has been disconnected for a very long time and the log chain is broken, it may need to be reseeded (remove and re-add from backup). This is a last resort.

## Related scripts

- [`Get-WaitStatistics`](../wait-statistics/index.md) — `HADR_SYNC_COMMIT` appears when a synchronous secondary is lagging; `WRITELOG` is often co-elevated
- [`Get-BackupCoverage`](../backup-coverage/index.md) — if using AG secondary for backups, ensure that coverage is tracked

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/high-availability/Get-AvailabilityGroupReplicaState.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/high-availability/Get-AvailabilityGroupReplicaState.sql)
- [`sql/high-availability/Get-AvailabilityGroupLatency.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/high-availability/Get-AvailabilityGroupLatency.sql)

---

## SEO

**Focus keyphrase:** SQL Server availability group health

**Meta description** (trim to 160 before publishing):  
Monitor SQL Server Always On Availability Group replica state, connection health, and synchronization lag with two scripts covering replica and database-level status.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `ag-replica-state-output.png` | Get-AvailabilityGroupReplicaState output showing ag_name, replica roles, connected_state and synchronization_health columns | AG replica state output |
| `ag-latency-output.png` | Get-AvailabilityGroupLatency output showing log_send_queue_size and redo_queue_size per database per secondary replica | AG sync queue and latency |
