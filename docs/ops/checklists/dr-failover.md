# DR Failover and Failback Checklist

Use for: disaster recovery failover (planned DR test or actual disaster) and subsequent failback.
Covers: log shipping DR, AG DR failover, and manual database restore scenarios.

---

## Context

**DR Type:**  `[ ] Log Shipping  [ ] Always On AG  [ ] Manual Restore  [ ] Other: ___________`
**Scenario:** `[ ] Planned DR test  [ ] Actual disaster — source unavailable`
**Primary site:** `___________`
**DR site:**     `___________`

---

## Section 1 — Planned DR Test Failover

### Pre-Test

- [ ] Change order approved for DR test window
- [ ] DR test scope documented: which databases, which applications
- [ ] Application team available for connectivity testing during DR test
- [ ] Monitoring team notified — suppress alerts from primary during DR test window
- [ ] DR server OS, SQL Server version, and patch level documented
- [ ] Last successful DR restore date confirmed: `___________`
- [ ] `Export-MigrationBaseline.ps1 -Label pre` run against DR server (captures DR state before test)

### DR Test Execution

**For Log Shipping DR:**
- [ ] Stop log shipping copy/restore jobs on DR server (simulates production cutover)
- [ ] Take final log backup on primary and ship to DR manually (if primary is reachable)
- [ ] Restore final log backup WITH RECOVERY on DR server: `RESTORE DATABASE [dbname] WITH RECOVERY`
- [ ] Confirm databases are ONLINE on DR server

**For AG DR (force failover — DR replica is async):**
- [ ] Force failover with data loss (required for async replica without quorum):
  ```sql
  ALTER AVAILABILITY GROUP [AGName] FORCE_FAILOVER_ALLOW_DATA_LOSS;
  ```
- [ ] Confirm AG is in PRIMARY state on DR: `SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1`

**All DR types:**
- [ ] DNS alias or application connection strings updated to DR site
- [ ] Application connectivity confirmed on DR server: `___________`
- [ ] SQL Agent jobs started on DR (ensure jobs are enabled on DR server)
- [ ] Backup jobs confirmed — DR server should now be the backup target

### DR Test Validation

- [ ] Critical application transactions tested on DR: `___________`
- [ ] `Get-DatabaseHealth.sql` — all databases ONLINE on DR server
- [ ] `Get-SqlAgentJobOverview.sql` — jobs running on DR
- [ ] `Get-BackupCoverage.sql` — backup chain active on DR
- [ ] DR server performance within acceptable range: `Get-WaitStatistics.sql`
- [ ] DR test evidence captured (screenshots, CSV output) and attached to change order

### Return to Primary (After DR Test)

**For Log Shipping:**
- [ ] Put DR databases back into NORECOVERY/STANDBY mode for log shipping to resume:
  ```sql
  RESTORE DATABASE [dbname] WITH STANDBY = 'C:\standby\dbname.BAK';
  ```
  Or restart log shipping from scratch with a new full backup.
- [ ] Restart log shipping copy/restore jobs on DR server
- [ ] Confirm log shipping latency returns to baseline

**For AG:**
- [ ] Reconnect DR replica to original primary AG (manual seeding or automatic)
- [ ] Confirm replica returns to SYNCHRONIZED state

- [ ] Flip DNS alias or connection strings back to primary site
- [ ] Confirm application reconnects to primary: `___________`

---

## Section 2 — Actual Disaster Failover

### Immediate Actions (First 15 Minutes)

- [ ] Primary site confirmed unavailable — record time of failure: `___________`
- [ ] Escalation chain notified: DBA Lead, Application Owner, Management
- [ ] Decision to failover confirmed by: `___________` at `___________`
- [ ] Change manager notified (emergency change if required)

### DR Failover — Log Shipping

- [ ] Determine last log backup applied on DR: `SELECT * FROM msdb.dbo.log_shipping_monitor_secondary`
- [ ] Record last restore time: `___________` (this is your RPO — data loss point)
- [ ] If any un-applied log backups exist and primary storage is accessible — apply them now
- [ ] Bring databases online: `RESTORE DATABASE [dbname] WITH RECOVERY`
- [ ] Confirm all databases ONLINE

### DR Failover — Always On AG (Force Failover)

- [ ] Confirm primary replica is truly unavailable (not just a network blip)
- [ ] Check async replica's synchronisation state and estimated data loss:
  ```sql
  SELECT log_send_queue_size, log_send_rate FROM sys.dm_hadr_database_replica_states WHERE is_local = 1;
  ```
- [ ] Confirm acceptable data loss with business stakeholders: `___________`
- [ ] Force failover:
  ```sql
  ALTER AVAILABILITY GROUP [AGName] FORCE_FAILOVER_ALLOW_DATA_LOSS;
  ```
- [ ] Confirm DR replica is now PRIMARY

### Post-Failover (Actual Disaster)

- [ ] `Get-DatabaseHealth.sql` — all databases ONLINE on DR
- [ ] `Get-BackupCoverage.sql` — take immediate full backup of all databases on DR
- [ ] Application connectivity confirmed: `___________`
- [ ] SQL Agent jobs enabled and running on DR
- [ ] Identify and document RPO (data loss) and RTO (downtime) achieved
- [ ] Business stakeholders notified: DR failover complete, estimated data loss: `___________`
- [ ] Incident ticket raised — log all actions with timestamps

---

## Section 3 — Failback to Primary (After Disaster Recovery)

- [ ] Primary site confirmed recovered and available
- [ ] Primary server SQL Server service confirmed STOPPED (prevents split-brain)
- [ ] Failback plan agreed with business — confirm acceptable failback window
- [ ] Change order raised for failback

**For Log Shipping failback:**
- [ ] Take full backup of all DR databases
- [ ] Restore to primary in STANDBY or NORECOVERY
- [ ] Resume log shipping (DR → primary) until logs are caught up
- [ ] Quiesce writes on DR, apply final logs, bring primary databases ONLINE WITH RECOVERY

**For AG failback:**
- [ ] Reconnect primary replica to AG (add back as secondary)
- [ ] Wait for SYNCHRONIZED state on primary replica
- [ ] Planned failover back to original primary: `ALTER AVAILABILITY GROUP [AGName] FAILOVER`

**After failback:**
- [ ] Flip DNS alias or connection strings back to primary site
- [ ] Confirm application on primary: `___________`
- [ ] DR server returned to log shipping / async replica standby
- [ ] Post-incident review scheduled

---

## Sign-Off

| Role                  | Name | Signature | Date |
|-----------------------|------|-----------|------|
| DBA (lead)            |      |           |      |
| Application owner     |      |           |      |
| Incident manager      |      |           |      |