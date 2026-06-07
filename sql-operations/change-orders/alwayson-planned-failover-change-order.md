# Change Order — Always On AG Planned Failover / Replica Maintenance

> **Instructions:** Complete all fields before CAB submission.
> Use for: planned manual failover, replica addition/removal, or AG listener changes.

---

## 1. Change Metadata

| Field                   | Value |
|-------------------------|-------|
| Change Request Number*  | `[CR-XXXXX]` |
| Change Type*            | `[ ] Standard  [ ] Normal` |
| Risk Rating*            | `[ ] LOW  [ ] MEDIUM  [ ] HIGH` |
| Requested by*           | `[Name, Team]` |
| Technical lead*         | `[DBA Name]` |
| Change manager          | `[Name]` |

**Change Window***

| | Value |
|-|-------|
| Start date/time    | `[YYYY-MM-DD HH:MM]` |
| End date/time      | `[YYYY-MM-DD HH:MM]` |
| Rollback deadline  | `[YYYY-MM-DD HH:MM]` |
| Estimated duration | `[X minutes]` |
| Rollback duration  | `[X minutes]` — failover back to original primary |

---

## 2. Change Summary

**AG name:** `[AGName]`
**Listener name:** `[ListenerName]`
**Current primary:** `[SERVERNAME\INSTANCE]`
**Target primary (after failover):** `[SERVERNAME\INSTANCE]`

**Change type:**
```text
[ ] Planned manual failover — maintenance on current primary
[ ] Add new replica to AG
[ ] Remove replica from AG
[ ] AG listener IP change
[ ] Other: ___________
```

**Reason:**
```text
[Reason — e.g., OS patching on primary, hardware maintenance, server decommission]
```

---

## 3. Risk Assessment

| Risk | Mitigation |
|------|------------|
| AG not SYNCHRONIZED at failover time | Pre-check confirms SYNCHRONIZED + zero redo queue before proceeding |
| Application connects to primary by server name (not listener) | Application team confirms listener usage before failover |
| SQL Agent jobs don't fire on new primary | Jobs reviewed — `sys.fn_hadr_is_primary_replica()` guards confirmed |
| AG cannot resynchronise after failover | Failover back to original primary is possible within rollback deadline |
| Listener DNS does not update | DNS TTL confirmed low (< 5 min); client reconnect confirmed |

**Overall risk rating:** `[ ] LOW  [ ] MEDIUM  [ ] HIGH`

---

## 4. Pre-Change Validation (Go / No-Go)

| # | Check | Pass Criteria | Status |
|---|-------|---------------|--------|
| 1 | All replicas SYNCHRONIZED | `Get-AvailabilityGroupReplicaState.sql` — all SYNCHRONIZED | `[ ] PASS  [ ] FAIL` |
| 2 | Zero redo queue on target replica | `Get-AvailabilityGroupLatency.sql` — redo_queue_size = 0 | `[ ] PASS  [ ] FAIL` |
| 3 | Application uses listener (not direct server name) | Application team confirmed: ___________________________ | `[ ] PASS  [ ] FAIL` |
| 4 | AG listener DNS TTL is < 5 minutes | TTL confirmed with network team: ___________________________ | `[ ] PASS  [ ] FAIL` |
| 5 | No active long-running transactions | `Get-LongRunningQueries.sql` — no queries > 5 minutes | `[ ] PASS  [ ] FAIL` |
| 6 | Change approved | CAB approval on record | `[ ] PASS  [ ] FAIL` |

---

## 5. Implementation Steps — Planned Manual Failover

| Step | Action | Est. Time | Actual Start |
|------|--------|-----------|--------------|
| 1 | Confirm AG health: all replicas SYNCHRONIZED | 5 min | |
| 2 | Confirm redo queue = 0 on target replica | 2 min | |
| 3 | Notify application teams — failover beginning | 5 min | |
| 4 | Quiesce writes (confirm with application team) | 5 min | |
| 5 | Wait for log_send_queue_size = 0 | 2 min | |
| 6 | Initiate manual failover from target replica: `ALTER AVAILABILITY GROUP [AGName] FAILOVER` | 1 min | |
| 7 | Confirm target is PRIMARY — record time | 2 min | |
| 8 | Confirm AG listener resolves to new primary | 5 min | |
| 9 | Confirm application reconnects via listener | 5 min | |
| 10 | Confirm old primary is SECONDARY and SYNCHRONIZED | 10 min | |
| 11 | Notify stakeholders — failover complete | 5 min | |

**Total estimated duration:** ~45 minutes

---

## 6. Post-Change Validation

| Check | Pass Criteria |
|-------|---------------|
| New primary confirmed | `SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1` = 'PRIMARY' |
| All AG databases ONLINE | `SELECT name, state_desc FROM sys.databases WHERE state <> 0` = 0 rows |
| All replicas SYNCHRONIZED | `Get-AvailabilityGroupReplicaState.sql` — all SYNCHRONIZED |
| Application connectivity | Application team confirmed connected: ___________________________ |
| SQL Agent jobs running | `Get-SqlAgentJobOverview.sql` — enabled jobs present on new primary |
| Backup jobs running | Confirm backup jobs targeting new primary or preferred replica |

---

## 7. Rollback Plan

A planned failover is reversible by failing back to the original primary.

**Triggers:**
- AG does not complete failover within 5 minutes
- Application cannot connect within 15 minutes
- Any AG databases fail to come ONLINE
- Old primary cannot resynchronise as secondary within 30 minutes

**Rollback steps:**

| Step | Action |
|------|--------|
| 1 | Confirm original primary has joined as SECONDARY and is SYNCHRONIZED |
| 2 | From original primary: `ALTER AVAILABILITY GROUP [AGName] FAILOVER` |
| 3 | Confirm original primary is PRIMARY again |
| 4 | Confirm application reconnects via listener |
| 5 | Notify stakeholders — rollback complete |

---

## 8. Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Technical lead (DBA) | | | |
| Application owner | | | |
| Change manager / CAB | | | |
