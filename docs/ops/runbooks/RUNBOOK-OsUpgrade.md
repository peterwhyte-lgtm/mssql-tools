# Windows Server OS Upgrade Runbook

Upgrading the Windows Server OS on a machine running SQL Server — either in-place (same hardware) or side-by-side (new servers).

**Applies to:** Windows Server 2012 R2 – 2022 · SQL Server 2014–2022

---

## Which approach should I use?

| Scenario | Approach | Downtime |
|----------|---------|---------|
| New hardware, want new OS | Side-by-side — build new servers, migrate SQL via Standalone runbook | Cutover window only |
| Same hardware, VM, or cloud VM resize | In-place OS upgrade | Full window (hours) |
| Windows Server cluster (FCI or AG) | Rolling cluster OS upgrade | Rolling — no downtime if done correctly |
| SQL Server Web Edition, new hardware | Side-by-side — always preferred for 50-server scale | Cutover window only |

---

## SQL Server / Windows Server compatibility matrix

| SQL Server | Min Windows Server | Max Windows Server |
|-----------|-------------------|-------------------|
| SQL 2012 | 2008 R2 SP1 | 2016 |
| SQL 2014 | 2008 R2 SP1 | 2019 |
| SQL 2016 | 2012 | 2022 |
| SQL 2017 | 2016 | 2022 |
| SQL 2019 | 2016 | 2022 |
| SQL 2022 | 2019 | 2022 |

> **SQL 2022 requires Windows Server 2019 or 2022.** If you are migrating to SQL 2022, you must also be on WS2019+. Combine the OS upgrade with the SQL Server version upgrade using the side-by-side approach.

### Supported in-place Windows upgrade paths

| From | To |
|------|----|
| Windows Server 2012 R2 | 2016 → 2019 → 2022 (can skip one step) |
| Windows Server 2016 | 2019, 2022 |
| Windows Server 2019 | 2022 |

> In-place upgrades skip at most one version (WS2016 → WS2022 is supported). WS2012 R2 → WS2022 requires WS2016 or WS2019 as an intermediate step.

---

## Side-by-side OS upgrade (recommended for production at scale)

For 50 servers, this means building new Windows Server VMs/hardware at the target OS version and migrating SQL Server using the existing migration runbooks. No additional OS-specific steps are required — the SQL Server migration handles everything.

**Procedure:**
1. Build new servers at the target Windows Server version
2. Install SQL Server (same or new version — see [RUNBOOK-SqlVersionUpgrade.md](RUNBOOK-SqlVersionUpgrade.md))
3. Follow [RUNBOOK-Standalone.md](RUNBOOK-Standalone.md) for database/login/job migration
4. DNS cutover

---

## In-place Windows Server upgrade

**When to use:** Upgrading a single server or small fleet, where building new hardware/VMs is impractical.

### Pre-upgrade checklist

- [ ] Current SQL Server version is compatible with the target Windows Server version (see matrix above)
- [ ] Full database backups taken and verified
- [ ] System state backup taken (Windows Server Backup)
- [ ] Disk space: at least 32 GB free on the system drive
- [ ] .NET Framework version requirements checked (see below)
- [ ] All pending Windows Updates installed on current OS
- [ ] Antivirus / endpoint protection temporarily paused for duration of upgrade
- [ ] `Invoke-MigrationPreFlightCheck.ps1` confirms both SQL instances are healthy

```powershell
# Full health check and database backup before OS upgrade
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01

.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\backups\Generate-FullBackupScript.sql `
    -ServerInstance PROD01 `
    -OutputFormat DdlFile `
    -OutputPath output-files\migration\pre-os-upgrade-backup.sql
# Edit @BackupPath in the output, then run it
```

### .NET Framework requirements

SQL Server relies on specific .NET Framework versions. Windows Server upgrades may change the .NET version available:

| SQL Server | Minimum .NET |
|-----------|-------------|
| SQL 2012–2014 | .NET 3.5 SP1 |
| SQL 2016–2017 | .NET 4.6 |
| SQL 2019–2022 | .NET 4.7.2 or later |

Windows Server 2022 ships with .NET 4.8. This is compatible with all SQL Server versions. If upgrading from WS2016 to WS2019, .NET 4.8 may be installed automatically — this is fine for SQL Server.

### Step 1 — Stop SQL Server Agent (recommended, not required)

Prevents jobs from firing during the upgrade process:

```sql
-- Stop SQL Server Agent job execution
USE msdb;
EXEC sp_stop_job @job_name = N'<any running jobs>';
```

Or stop the SQL Server Agent service:

```powershell
Stop-Service SQLSERVERAGENT -Force
# For named instance: Stop-Service "SQLAgent$INSTANCENAME" -Force
```

### Step 2 — Run the Windows Server upgrade

Run Windows Server setup from the installation media. Choose **Upgrade: Install Windows and keep files, settings, and applications**.

```cmd
REM From Windows Server installation media:
setup.exe
REM → Upgrade: Install Windows and keep files, settings, and applications
REM → Select the correct edition to match your Windows Server licence
```

The upgrade process typically takes 1–3 hours. SQL Server services are **automatically stopped and restarted** by the Windows upgrade process.

### Step 3 — Post-upgrade SQL Server validation

```sql
-- Verify SQL Server started successfully
SELECT @@VERSION;
SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)) AS version;
SELECT CAST(SERVERPROPERTY('Edition') AS VARCHAR(128)) AS edition;

-- Check all databases are ONLINE
SELECT name, state_desc FROM sys.databases ORDER BY database_id;

-- Check for post-upgrade errors
EXEC xp_readerrorlog 0, 1, NULL, NULL, NULL, NULL, N'desc';
```

### Step 4 — Check Windows Server features and TLS settings

Windows Server upgrades can change cryptographic provider settings. SQL Server connections using TLS may be affected:

```powershell
# Check TLS 1.2 is enabled (required for SQL Server 2016+)
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -ErrorAction SilentlyContinue

# If not present or disabled, enable TLS 1.2:
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
New-Item -Path $path -Force | Out-Null
Set-ItemProperty -Path $path -Name Enabled -Value 1
Set-ItemProperty -Path $path -Name DisabledByDefault -Value 0
```

### Step 5 — Start SQL Server Agent and verify jobs

```powershell
Start-Service SQLSERVERAGENT
# For named instance: Start-Service "SQLAgent$INSTANCENAME"
```

```sql
-- Check jobs that ran during or after upgrade
SELECT j.name, h.run_date, h.run_time, h.run_status,
       SUBSTRING(h.message, 1, 200) AS message
FROM msdb.dbo.sysjobhistory h
INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE h.run_date >= CAST(FORMAT(GETDATE(), 'yyyyMMdd') AS INT) - 1
ORDER BY h.run_date DESC, h.run_time DESC;
```

### Step 6 — Run health check

```powershell
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

---

## Rolling cluster OS upgrade (WSFC with AG or FCI)

For Windows Server Failover Clusters running SQL Server AGs or FCIs, Windows Server 2016+ supports **rolling OS upgrades** — upgrading one node at a time while the cluster remains operational.

**Requires:**
- Windows Server 2016 or later on all nodes (to support mixed-OS clusters during upgrade)
- SQL Server 2016 or later
- All nodes in the cluster must eventually reach the new OS version

### Phase 1 — Upgrade passive nodes first

```powershell
# 1. Pause the node being upgraded in the cluster
Suspend-ClusterNode -Name SQLNODE02

# 2. Drain roles off the node (move any cluster resources to other nodes)
Move-ClusterGroup -Name 'AG_GroupName' -Node SQLNODE01
```

3. Run the Windows Server in-place upgrade on SQLNODE02 (see above)

4. After upgrade, resume the node:

```powershell
Resume-ClusterNode -Name SQLNODE02
```

5. Verify the node rejoined the cluster and synchronised:

```sql
-- Check AG replica sync state
SELECT ar.replica_server_name, ars.role_desc, ars.synchronization_health_desc
FROM sys.dm_hadr_availability_replica_states ars
INNER JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id;
```

Wait until `synchronization_health_desc = HEALTHY` before proceeding to the next node.

### Phase 2 — Fail over to upgraded node, then upgrade primary

```sql
-- Manual failover to the upgraded secondary (brief interruption)
ALTER AVAILABILITY GROUP [AGName] FAILOVER;
```

Now upgrade the original primary node using the same process.

### Phase 3 — Update the cluster functional level

After all nodes are on the new OS:

```powershell
Update-ClusterFunctionalLevel
```

This is a one-way operation — after this, the cluster cannot run on the previous OS version.

---

## Post-upgrade rollback

**In-place OS upgrade:** Windows does not support downgrading an OS after in-place upgrade. Your only rollback options are:
- Restore from a full system backup (VSS / Windows Server Backup taken before upgrade)
- Restore to a VM snapshot (if running on a hypervisor)

This is why you should always take a system state backup and database backups before starting.

**Side-by-side / rolling:** The source server remains intact — revert DNS to the source.

---

## Key gotchas

| Issue | What happens | Fix |
|-------|------------|-----|
| TLS protocol settings reset | Applications get TLS handshake errors after upgrade | Re-enable TLS 1.2 (Step 4 above) |
| .NET Framework version changed | SQL CLR assemblies may fail | Verify .NET 4.x compatibility |
| Firewall rules reset | SQL port 1433 blocked after upgrade | Re-add inbound rule for port 1433 |
| SQL Server service account permissions | Group Policy re-applied, service account may lose rights | Run SQL Server Configuration Manager to verify service accounts |
| Cluster functional level | Mixed-OS cluster runs at lower functional level until `Update-ClusterFunctionalLevel` | Run after all nodes are upgraded |
| SQL Server error log flooded | Informational noise after restart on new OS | Normal — review for ERROR-level entries only |

---

## Script quick-reference

| Script | When to run |
|--------|------------|
| `Invoke-HealthCheckCollection.ps1` | Before upgrade (baseline) and after upgrade (validation) |
| `Generate-FullBackupScript.sql` | Before upgrade — create verified backup |
| `Get-VersionUpgradeReadiness.ps1` | If also upgrading SQL Server version at same time |
| `Invoke-MigrationPreFlightCheck.ps1` | Side-by-side: before migration window |
| `Get-AvailabilityGroupReplicaState.sql` | Rolling cluster upgrade: between node upgrades |
