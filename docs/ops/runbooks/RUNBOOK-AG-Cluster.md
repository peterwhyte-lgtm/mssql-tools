# SQL Server AG / FCI Migration Runbook

Migrating SQL Server instances that are part of an **Always On Availability Group (AG)** or a **Failover Cluster Instance (FCI)**. Both scenarios require different sequencing from a standalone migration.

**Applies to:** SQL Server 2016–2022 · Standard / Enterprise Edition · Windows Server

---

## Which playbook do you need?

| Scenario | Use |
|----------|-----|
| Standalone instance → new hardware | [RUNBOOK-Standalone.md](RUNBOOK-Standalone.md) |
| AG (replicated databases) → new hardware | [AG playbook](#ag-migration) in this document |
| FCI (shared-disk cluster) → new hardware | [FCI playbook](#fci-migration) in this document |
| AG → AG (same databases, new servers) | AG playbook |
| FCI → AG (topology change) | FCI playbook + AG build, then failover |

---

## AG migration

### Overview

The preferred AG migration approach adds new replica nodes to the existing AG, fails over to the new primary, then removes the old nodes. This approach minimises downtime to the time of a planned failover (typically < 30 seconds).

**Requires:** Enterprise Edition for multi-database AGs on older versions. Standard Edition supports Basic AGs (single-database, SQL 2016+).

```text
Before:
  [OLDPRI] ──sync──► [OLDSEC1]   ← existing AG

During transition:
  [OLDPRI] ──sync──► [OLDSEC1]
       └──sync──► [NEWSEC1]   ← new replica added

After failover:
  [NEWPRI] ──sync──► [NEWSEC1]   ← new AG
  (OLDPRI and OLDSEC1 removed)
```

### Phase 1 — Prepare new replica nodes

#### 1.1 Install SQL Server on new nodes

Match the same edition, version, and patch level as the source AG. Check source:

```sql
SELECT @@VERSION;
SELECT SERVERPROPERTY('ProductVersion'), SERVERPROPERTY('ProductLevel'), SERVERPROPERTY('Edition');
```

#### 1.2 Join new nodes to the Windows Server Failover Cluster (WSFC)

New nodes must join the same WSFC as the existing AG. In Server Manager → Failover Cluster Manager → Add Node. Validate the cluster after adding.

#### 1.3 Enable the Availability Groups feature on new nodes

```powershell
# On each new node — run in elevated PowerShell
Enable-SqlAlwaysOn -ServerInstance 'NEWNODE1\INST' -Force
# Restart SQL Server service after enabling
Restart-Service MSSQLSERVER   # or the named instance service
```

#### 1.4 Configure endpoint on new replicas

```sql
-- On each new replica node
-- Check if endpoint already exists
SELECT * FROM sys.database_mirroring_endpoints;

-- If not, create it:
CREATE ENDPOINT [Hadr_endpoint]
    STATE = STARTED
    AS TCP (LISTENER_PORT = 5022)
    FOR DATABASE_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES);

-- Grant CONNECT to the SQL Server service account
GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [DOMAIN\NewSqlSvcAcct];
```

#### 1.5 Create mirroring endpoint login on existing primary (if new service account)

```sql
-- On existing PRIMARY
-- The new replica's service account needs to connect to the mirroring endpoint
CREATE LOGIN [DOMAIN\NewSqlSvcAcct] FROM WINDOWS;
GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [DOMAIN\NewSqlSvcAcct];
```

---

### Phase 2 — Seed databases to new replica (initial synchronisation)

For large databases, seed manually before joining the AG to avoid AG synchronisation overhead.

#### 2.1 Take backup of all AG databases on current primary

Backups go to a share accessible by the new replica nodes:

```powershell
# From repo root — generates BACKUP DATABASE for all online user databases
.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\backups\Generate-FullBackupScript.sql `
    -ServerInstance OLDPRI `
    -OutputFormat DdlFile `
    -OutputPath output-files\migration\ag-full-backup.sql

# Edit @BackupPath in ag-full-backup.sql, then run it on OLDPRI
```

Also take a log backup immediately after the full (to establish the log chain):

```sql
DECLARE @BackupPath nvarchar(260) = N'\\BACKUP-SERVER\SQL-Backups';
-- Repeat for every AG database:
BACKUP LOG [dbname] TO DISK = @BackupPath + '\dbname_LOG_init.bak' WITH STATS = 5;
```

#### 2.2 Restore databases on new replica nodes WITH NORECOVERY

```sql
-- On new replica nodes (NEWSEC1, NEWSEC2, etc.)
-- Use Generate-RestoreWithMoveScript.sql with @WithRecovery = 0 (NORECOVERY)
-- This leaves databases in RESTORING state, ready to join the AG

-- Set in restore-with-move.sql:
DECLARE @WithRecovery bit = 0;   -- NORECOVERY = leave in restoring state

-- Run full restore, then apply the initial log backup:
RESTORE LOG [dbname] FROM DISK = N'\\BACKUP-SERVER\SQL-Backups\dbname_LOG_init.bak'
    WITH NORECOVERY;
```

---

### Phase 3 — Add new replicas to the AG

Run on the **current primary**:

```sql
-- Check current AG state
SELECT
    ag.name                 AS ag_name,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.connected_state_desc
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;
```

```sql
-- Add new replica to the AG
-- Adjust availability_mode, failover_mode, seeding_mode to match your configuration
ALTER AVAILABILITY GROUP [AGName]
    ADD REPLICA ON N'NEWSEC1'
    WITH (
        ENDPOINT_URL      = N'TCP://NEWSEC1.corp.example.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,       -- or ASYNCHRONOUS_COMMIT
        FAILOVER_MODE     = AUTOMATIC,                 -- or MANUAL
        SEEDING_MODE      = MANUAL,                   -- MANUAL because we pre-seeded
        SECONDARY_ROLE (ALLOW_CONNECTIONS = NO)
    );
```

On the **new replica**, join it to the AG:

```sql
-- On NEWSEC1
ALTER AVAILABILITY GROUP [AGName] JOIN;
```

For each AG database on the new replica, join it:

```sql
-- On NEWSEC1 — for each database in the AG
ALTER DATABASE [dbname] SET HADR AVAILABILITY GROUP = [AGName];
```

---

### Phase 4 — Monitor synchronisation

Watch until all databases are SYNCHRONIZED:

```sql
-- On primary — check sync state
SELECT
    ar.replica_server_name,
    drs.database_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.redo_queue_size,      -- KB of log still to apply on secondary
    drs.redo_rate             -- KB/sec being applied
FROM sys.dm_hadr_database_replica_states drs
INNER JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
WHERE ar.replica_server_name IN ('NEWSEC1', 'NEWPRI')
ORDER BY ar.replica_server_name, drs.database_name;
```

Wait until `redo_queue_size` reaches 0 and `synchronization_state_desc = 'SYNCHRONIZED'` for all databases before proceeding to failover.

---

### Phase 5 — Planned failover to new primary

**This is the brief downtime window.** Connections to the AG listener will be interrupted for the duration of the failover (typically 10–30 seconds).

#### 5.1 Confirm application teams are ready for the brief interruption

#### 5.2 If failing over to a node in a different subnet, update listener IP

```sql
-- On current primary — add the new subnet's IP to the listener
ALTER AVAILABILITY GROUP [AGName]
    MODIFY LISTENER 'AGListenerName' (ADD IP ('10.0.2.100', '255.255.255.0'));
```

#### 5.3 Execute the planned manual failover

```sql
-- On NEWSEC1 (the intended new primary)
ALTER AVAILABILITY GROUP [AGName] FAILOVER;
```

#### 5.4 Verify the new primary is running

```sql
SELECT
    ars.role_desc,
    ar.replica_server_name,
    ars.synchronization_health_desc
FROM sys.dm_hadr_availability_replica_states ars
INNER JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id
WHERE ars.role_desc = 'PRIMARY';
```

---

### Phase 6 — Update listener DNS / remove old replicas

#### 6.1 Remove old replicas from the AG (after validation)

```sql
-- On new primary (NEWPRI)
ALTER AVAILABILITY GROUP [AGName] REMOVE REPLICA ON N'OLDPRI';
ALTER AVAILABILITY GROUP [AGName] REMOVE REPLICA ON N'OLDSEC1';
```

#### 6.2 Remove old nodes from the WSFC

In Failover Cluster Manager → Remove Node for each old node after the AG is stable.

#### 6.3 Update external DNS if the AG listener name is changing

If you need to rename the listener or the listener IP has changed:

```powershell
# Update DNS A record for the listener name
$zone     = 'corp.example.com'
$record   = 'AGListenerName'
$newIP    = '10.0.2.100'

$old = Get-DnsServerResourceRecord -ZoneName $zone -Name $record -RRType A
$new = $old.Clone()
$new.RecordData.IPv4Address = $newIP
Set-DnsServerResourceRecord -ZoneName $zone -OldInputObject $old -NewInputObject $new
```

Update SPNs for the listener (Windows Auth):

```cmd
setspn -D MSSQLSvc/AGListenerName:1433          DOMAIN\OldSqlSvcAcct
setspn -A MSSQLSvc/AGListenerName:1433          DOMAIN\NewSqlSvcAcct
setspn -A MSSQLSvc/AGListenerName.corp.example.com:1433 DOMAIN\NewSqlSvcAcct
```

---

### Phase 7 — Post-migration validation (AG)

```powershell
# Run health check against the new primary
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance NEWPRI
.\powershell\reporting\Review-HealthCheckOutput.ps1

# Confirm AG replica sync state
.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\high-availability\always-on\Get-AvailabilityGroupReplicaState.sql `
    -ServerInstance NEWPRI
```

Validate:
- All databases are PRIMARY/SECONDARY (not RESOLVING)
- `synchronization_health_desc = HEALTHY`
- Listener is reachable: `Test-NetConnection -ComputerName AGListenerName -Port 1433`

---

### AG rollback procedure

If the failover fails or the new primary has issues:

```sql
-- Failback to original primary
-- On OLDPRI (make sure it is still reachable)
ALTER AVAILABILITY GROUP [AGName] FAILOVER;
```

If OLDPRI was already removed from the AG, you need to force failover (potential data loss):

```sql
-- Force failover — only if no other option
-- Data loss is possible if secondary was not synchronized
ALTER AVAILABILITY GROUP [AGName] FORCE_FAILOVER_ALLOW_DATA_LOSS;
-- Then immediately run DBCC CHECKDB on all AG databases
```

---

---

## FCI migration

### Overview

A Failover Cluster Instance (FCI) uses shared storage. Migration typically means:
1. Building a new FCI with new hardware
2. Establishing a backup-based data sync (or log shipping) to the new FCI
3. Planned failover window: stop app traffic, final sync, bring new FCI online
4. DNS cutover

> If the new FCI can use the same Windows cluster, consider an in-place node addition followed by evicting old nodes. The steps below assume a completely new cluster is being built.

### Phase 1 — Build the new FCI

1. Build the Windows Server Failover Cluster on the new nodes
2. Install SQL Server as a clustered instance (use the same instance name to simplify connection string migration)
3. Use the same SQL Server service account (SID matters for SPN registration)
4. Configure a different SQL Server network name if running in parallel — you will rename/DNS-switch at cutover

Recommended: use a different temporary name (e.g. `PROD01-NEW`) during build, then perform a DNS swap at cutover to make it answer as `PROD01`.

### Phase 2 — Sync databases to new FCI via backup/restore + log shipping

For a long cutover-free sync period, use log shipping:

#### 2.1 Initial seed (full + differential backups)

```powershell
# Generate full backup script — run on SOURCE FCI primary
.\powershell\migration\Invoke-MigrationExport.ps1 -ServerInstance PROD01
# Execute full-backup.sql on source FCI
```

Restore all databases on the new FCI with `NORECOVERY`:

```sql
-- Use Generate-RestoreWithMoveScript.sql with @WithRecovery = 0
-- Adjust path parameters for the new FCI's drive layout
```

#### 2.2 Set up log shipping (for ongoing sync during preparation)

```sql
-- On source FCI primary — backup the log for each database
-- Ship log backups to a share accessible by the new FCI
-- Restore each log backup on new FCI WITH NORECOVERY (keep in restoring state)

-- Automate this with a SQL Agent job that runs every 5–15 minutes
```

### Phase 3 — Maintenance window: final cutover

1. **Stop application traffic** to the source FCI (disable connections or take SQL Server offline)
2. Take a final log backup on source FCI and restore on new FCI
3. Bring all new FCI databases online: `RESTORE DATABASE [dbname] WITH RECOVERY;`
4. Migrate logins, agent jobs, linked servers using the export artifacts from Phase 2.1
5. Run `Fix-OrphanedUsers.sql` and `Get-PostMigrationValidation.sql` on new FCI
6. DNS cutover (same procedure as [Standalone Phase 7](RUNBOOK-Standalone.md#phase-7--dns-cutover))

### Phase 4 — Post-migration validation (FCI)

```powershell
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01-NEW
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

Confirm the Windows cluster resource group is online:

```powershell
Get-ClusterGroup | Format-Table Name, State, OwnerNode
```

### FCI rollback procedure

Source FCI is still intact with databases online (you took backups, not moved data). Revert DNS to the source FCI IP:

```powershell
$old = Get-DnsServerResourceRecord -ZoneName $zone -Name 'PROD01' -RRType A
$new = $old.Clone()
$new.RecordData.IPv4Address = '10.0.1.40'   # source FCI IP
Set-DnsServerResourceRecord -ZoneName $zone -OldInputObject $old -NewInputObject $new
```

---

## Timing estimates

### AG migration

| Phase | Estimate | Notes |
|-------|---------|-------|
| Phase 1 — Prepare replicas | 2–4 hours | Before window |
| Phase 2 — Initial seed | 2–12 hours | Depends on data size |
| Phase 3 — Join replicas | 30 min | |
| Phase 4 — Synchronisation | 1–4 hours | Wait for redo queue = 0 |
| Phase 5 — Planned failover | < 30 seconds | Actual downtime |
| Phase 6 — Remove old replicas | 15 min | After validation |
| Phase 7 — Validation | 30 min | |

### FCI migration

| Phase | Estimate | Notes |
|-------|---------|-------|
| Phase 1 — Build new FCI | 4–8 hours | Before window |
| Phase 2 — Initial seed + log shipping | 4–24 hours | Before window |
| Phase 3 — Maintenance window | 30–90 minutes | Actual downtime |
| Phase 4 — Validation | 30 min | |

---

## Script quick-reference

| Script | Purpose | Run on |
|--------|---------|--------|
| `Invoke-PreMigrationAssessment.ps1` | Full source assessment | Source primary |
| `Invoke-MigrationExport.ps1` | Generate all migration artifacts | Source primary |
| `Get-AvailabilityGroupReplicaState.sql` | AG replica sync status | AG primary |
| `Get-AvailabilityGroupLatency.sql` | AG replication latency | AG primary |
| `Generate-FullBackupScript.sql` | BACKUP all databases | Source primary |
| `Generate-RestoreWithMoveScript.sql` | RESTORE with path remapping | → Target |
| `Generate-LoginScript.sql` | CREATE LOGIN with SIDs | Source → Target |
| `Generate-AgentJobScript.sql` | Agent jobs DDL | Source → Target |
| `Generate-LinkedServerScript.sql` | Linked server DDL | Source → Target |
| `Fix-OrphanedUsers.sql` | Re-map DB users to logins | Target |
| `Get-PostMigrationValidation.sql` | Source vs target count diff | Both |
| `Invoke-HealthCheckCollection.ps1` | Full health check | Target |
