# Migration Rollback Playbook

This playbook defines when to rollback, who decides, and exactly how to execute rollback for each migration type. "If something goes wrong" is not a rollback plan.

---

## Rollback Decision Framework

### Who decides?

The rollback decision belongs to the **Technical Lead (DBA)** within the rollback window.
If the DBA is unavailable, escalate to: `[Name, Phone]`

The DBA does not need permission to rollback — if a trigger criterion is met, rollback begins immediately and stakeholders are notified in parallel.

**Never wait past the rollback deadline hoping things will improve.**

### Rollback window

The rollback window closes at the **rollback deadline** stated in the change order.
If validation is not complete by the rollback deadline: **rollback begins, regardless of partial progress.**

Record rollback deadline here: `[YYYY-MM-DD HH:MM]`

---

## Rollback Trigger Criteria

These are binary PASS/FAIL criteria. One FAIL = rollback begins.

| # | Trigger | Threshold |
|---|---------|-----------|
| 1 | User database not ONLINE | Any user database in non-ONLINE state > 15 minutes after migration step completes |
| 2 | Application connectivity failure | Application cannot connect to SQL Server > 20 minutes after cutover |
| 3 | AG replica not synchronised | AG secondary remains RESOLVING or NOT SYNCHRONIZING > 30 minutes after failover |
| 4 | Data loss detected | Row count mismatch on any critical table (compare against pre-migration baseline) |
| 5 | SQL Server not started | SQL Server service fails to start after upgrade or migration |
| 6 | Rollback deadline exceeded | Validation not complete and deadline has passed |
| 7 | Critical job failure | A P1-tier SQL Agent job fails on first post-migration execution |

If you are unsure whether a trigger has been met: assume it has and begin rollback. You can abort rollback if the situation resolves before you reach an irreversible step.

---

## Rollback Procedures by Migration Type

---

### Type A — Side-by-Side Migration (Backup/Restore)

**Rollback time estimate:** 5–10 minutes (DNS flip only)
**Rollback deadline risk:** LOW — source server is untouched

**Prerequisites for rollback to be possible:**
- Source server SQL Server service is still RUNNING
- DNS alias or connection strings have not been permanently updated at infrastructure level

**Steps:**

| Step | Action | Owner |
|------|--------|-------|
| 1 | Announce rollback to all stakeholders immediately — do not wait until complete | DBA |
| 2 | Flip DNS alias back to source server, OR restore application connection strings to source | DBA / Network |
| 3 | Restart SQL Server Agent on source (if it was stopped) | DBA |
| 4 | Confirm application reconnects to source: `[test query and expected result]` | App team |
| 5 | Record rollback complete time: ___________________________ | DBA |
| 6 | Do NOT stop SQL Server service on target — preserve it for investigation | DBA |
| 7 | Notify all stakeholders: rollback complete, post-incident review to be scheduled | DBA |

**Post-rollback:**
- Source server is authoritative — target server databases are stale and must not be used
- Schedule post-incident review within 48 hours
- Do not reattempt migration without reviewing root cause

---

### Type B — In-Place Upgrade

**Rollback time estimate:** 2–4 hours (restore from backup to new instance)
**Rollback deadline risk:** HIGH — in-place upgrades cannot be downgraded; rollback = full restore

> **SQL Server does not support downgrade.** An in-place upgrade cannot be reversed.
> Rollback requires restoring databases to a separate SQL Server instance from pre-migration backups.

**Prerequisites for rollback to be possible:**
- Pre-migration full backups exist and are accessible
- A parallel SQL Server instance is available (or can be stood up quickly)
- Rollback window is sufficient for full restore of all databases

**Steps:**

| Step | Action | Owner |
|------|--------|-------|
| 1 | Announce rollback — note this will take `[X hours]` | DBA |
| 2 | Stand up or identify the rollback SQL Server instance (old version) | DBA |
| 3 | Restore all databases from pre-migration backups WITH RECOVERY | DBA |
| 4 | Run login script on rollback instance | DBA |
| 5 | Fix orphaned users | DBA |
| 6 | Flip DNS alias or connection strings to rollback instance | DBA / Network |
| 7 | Confirm application connectivity on rollback instance | App team |
| 8 | Notify stakeholders: rollback complete | DBA |

**Mitigation for future attempts:** Prefer side-by-side migration to avoid this scenario.

---

### Type C — Always On AG Planned Failover

**Rollback time estimate:** 5–15 minutes (failover back)
**Rollback deadline risk:** LOW — original primary remains available as secondary

**Prerequisites:**
- Original primary has joined as AG secondary and is SYNCHRONIZED (or can be forced back)
- AG listener is still active

**Steps:**

| Step | Action | Owner |
|------|--------|-------|
| 1 | Confirm original primary is joined as SECONDARY | DBA |
| 2 | If original primary is SYNCHRONIZED: `ALTER AVAILABILITY GROUP [AGName] FAILOVER;` from original primary | DBA |
| 3 | If original primary is NOT SYNCHRONIZED: wait up to 10 minutes, then consider force failover with data loss — confirm acceptable data loss window with business | DBA + Business |
| 4 | Confirm original primary is back to PRIMARY role | DBA |
| 5 | Confirm application connects via listener | App team |
| 6 | Notify stakeholders: rollback complete | DBA |

---

### Type D — Log Shipping Cutover

**Rollback time estimate:** 5–10 minutes (DNS flip, restart source agent)
**Rollback deadline risk:** MEDIUM — depends on whether source databases were brought ONLINE WITH RECOVERY

> **Critical:** Once the source databases are brought online WITH RECOVERY for the cutover, the log shipping chain is broken. Rollback at that point requires a full reinitialisation of log shipping.

**Before final RESTORE WITH RECOVERY on source (early stages):**

| Step | Action |
|------|--------|
| 1 | Stop log shipping jobs on DR server |
| 2 | Re-enable log shipping jobs on source to resume shipping |
| 3 | Flip DNS alias or connection strings back to source |
| 4 | Confirm application on source |

**After RESTORE WITH RECOVERY on source (late stages):**

| Step | Action |
|------|--------|
| 1 | Flip DNS back to source |
| 2 | Confirm application on source |
| 3 | Source databases are now out of log shipping — reinitialise log shipping from new full backup after incident resolution |

---

## Communication Script

When rollback is initiated, use this communication template:

**Immediate notification (within 2 minutes of rollback decision):**
```text
Subject: [URGENT] Migration Rollback Initiated — [ServerName]

The [ServerName] migration is being rolled back due to: [trigger criterion].

Rollback in progress — estimated completion: [time].

Application connectivity will be restored to [source/original server] within [X minutes].

DBA Lead: [Name, Phone]
```

**Completion notification:**
```text
Subject: [RESOLVED] Migration Rollback Complete — [ServerName]

The [ServerName] migration rollback is complete.

Application connectivity restored to [source server] at [time].

Root cause investigation underway. Post-incident review scheduled for [date].

No further action required at this time.
```

---

## Post-Rollback Checklist

- [ ] Source system confirmed stable and applications operational
- [ ] Target server preserved for investigation (do not wipe)
- [ ] Incident ticket raised with full timeline of events
- [ ] Change order status updated to "Rolled Back"
- [ ] Post-incident review scheduled within 48 hours
- [ ] Root cause identified before reattempting migration
- [ ] Change order updated with root cause and corrective actions