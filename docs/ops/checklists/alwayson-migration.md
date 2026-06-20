# Always On Availability Groups Migration Checklist

Use for: adding/removing AG replicas, planned manual failovers, and AG migration to new infrastructure.
Change order template: `../change-orders/alwayson-planned-failover-change-order.md`

---

## Scenario A — Planned Manual Failover (Maintenance on Primary)

### Pre-Failover

- [ ] Confirm AG health: `Get-AvailabilityGroupReplicaState.sql` — all replicas SYNCHRONIZED
- [ ] Confirm AG latency is acceptable: `Get-AvailabilityGroupLatency.sql` — redo queue < 1 MB
- [ ] Confirm target replica (new primary) is SYNCHRONIZED, not just SYNCHRONIZING
- [ ] Confirm target replica has no unresolved redo queue: `redo_queue_size = 0`
- [ ] Notify application teams of planned failover window
- [ ] Change order approved for planned failover
- [ ] Identify AG listener name and IP — application teams confirm using listener (not direct server)
- [ ] Confirm all jobs that run against the primary replica are reviewed (will they fire on new primary?)
- [ ] Confirm database mail / linked servers on secondary are equivalent

### Failover Execution

- [ ] Quiesce application writes — confirm with application team: `___________`
- [ ] Wait for `log_send_queue_size = 0` on primary: `Get-AvailabilityGroupLatency.sql`
- [ ] Initiate manual failover from new primary (SSMS or T-SQL):
  ```sql
  ALTER AVAILABILITY GROUP [AGName] FAILOVER;
  ```
- [ ] Record failover start time: `___________`
- [ ] Confirm new primary is PRIMARY: `SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1`
- [ ] Confirm old primary is now SECONDARY/RESOLVING — expected to join as secondary
- [ ] Confirm AG listener resolves to new primary IP

### Post-Failover Validation

- [ ] All AG databases ONLINE on new primary: `SELECT name, state_desc FROM sys.databases WHERE name NOT IN ('master','model','msdb','tempdb')`
- [ ] All replicas back to SYNCHRONIZED: `Get-AvailabilityGroupReplicaState.sql`
- [ ] Application connectivity confirmed via listener: `___________`
- [ ] SQL Agent jobs running on new primary (jobs referencing `sys.fn_hadr_is_primary_replica`)
- [ ] Backup jobs running — confirm backup policy targets current primary or preferred replica
- [ ] AG latency back to baseline: `Get-AvailabilityGroupLatency.sql`

---

## Scenario B — Adding a New Replica (Server Migration via AG)

### Pre-Addition

- [ ] New server meets AG requirements: same or newer SQL Server version, Enterprise edition (for synchronous replicas)
- [ ] New server joined to Windows Server Failover Cluster (WSFC)
- [ ] Network connectivity confirmed between existing replicas and new server (port 5022 for mirroring endpoint)
- [ ] Sufficient disk space on new server for all AG databases (data + logs + backup working space)
- [ ] SQL Server service account has access to the AG endpoint
- [ ] Run `Invoke-PreMigrationAssessment.ps1` against new server — address any HIGH findings

### Adding the Replica

- [ ] Create AG endpoint on new server if it does not exist:
  ```sql
  CREATE ENDPOINT Hadr_endpoint STATE = STARTED AS TCP (LISTENER_PORT = 5022)
  FOR DATABASE_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES);
  ```
- [ ] Grant CONNECT on endpoint to SQL service account
- [ ] Add replica to AG (SSMS or T-SQL) — choose synchronous or asynchronous based on network latency
- [ ] Initial seeding: automatic seeding or manual backup/restore

**If manual seeding:**
- [ ] Take full backup of each AG database on primary
- [ ] Restore each database on new replica WITH NORECOVERY
- [ ] Join each database to AG: `ALTER DATABASE [dbname] SET HADR AVAILABILITY GROUP = [AGName]`

- [ ] Confirm new replica reaches SYNCHRONIZED state: `Get-AvailabilityGroupReplicaState.sql`
- [ ] Confirm redo queue drains to 0: `Get-AvailabilityGroupLatency.sql`

### Removing the Old Replica (After New Replica is SYNCHRONIZED)

- [ ] Old replica is confirmed SYNCHRONIZED and not the current primary
- [ ] Remove replica from AG:
  ```sql
  ALTER AVAILABILITY GROUP [AGName] REMOVE REPLICA ON N'OldServerName';
  ```
- [ ] Confirm AG health with 1 fewer replica: `Get-AvailabilityGroupReplicaState.sql`
- [ ] Update AG listener if IP subnet changed

---

## Scenario C — AG Migration to New Subnet / IP

- [ ] Plan AG listener IP change with network team — new IP and subnet confirmed
- [ ] Update listener IP:
  ```sql
  ALTER AVAILABILITY GROUP [AGName]
  MODIFY LISTENER N'ListenerName' (ADD IP (N'NewIP', N'SubnetMask'));
  ```
- [ ] Remove old IP from listener after DNS TTL expires (typically 5–15 minutes)
- [ ] Confirm listener resolves to new IP from application servers: `Test-NetConnection <listener> -Port 1433`
- [ ] Confirm application can connect via listener after IP change
- [ ] Update DNS records if using hostname-based listener

---

## Rollback Criteria

**Initiate rollback if ANY of the following:**
- Failover does not complete within 5 minutes
- AG databases do not come ONLINE on new primary within 10 minutes
- Application cannot connect via listener within 15 minutes of failover
- AG cannot resynchronise old replica within 30 minutes
- Data divergence detected between replicas

**Rollback — failover back to original primary:**
```sql
-- From original primary (now secondary), after confirming it is SYNCHRONIZED:
ALTER AVAILABILITY GROUP [AGName] FAILOVER;
```
