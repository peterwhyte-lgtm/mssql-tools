# SQL Server Edition Change Runbook

Changing the SQL Server edition on a running instance — upgrades (Web → Standard → Enterprise) and downgrades (Enterprise → Standard → Web).

**Applies to:** SQL Server 2016–2022 · Windows Server

---

## Edition hierarchy and key differences

```text
Express (free)  →  Web  →  Standard  →  Enterprise
```

| Capability | Express | Web | Standard | Enterprise |
|-----------|---------|-----|----------|-----------|
| Max RAM (buffer pool) | 1 GB | OS max | 128 GB | OS max |
| Max CPU sockets | 1 | 4 | 4 | OS max |
| Availability Groups | No | No (secondary only) | Basic AG (1 DB, 2 nodes) | Full AG (multiple DB, 9 nodes) |
| Readable AG secondary | No | No | No | Yes |
| TDE | No | No | No* | Yes |
| Database Snapshots | No | No | No | Yes |
| Resource Governor | No | No | No | Yes |
| Row/Page Compression | No | No | Yes (2016 SP1+) | Yes |
| Partitioning | No | No | Yes (2016 SP1+) | Yes |
| In-Memory OLTP | No | No | Limited (2016 SP1+) | Full |
| CDC | No | No | Yes (2016 SP1+) | Yes |
| Online Index Rebuild | No | No | No | Yes |
| Parallel Index Rebuild | No | No | No | Yes |

*TDE available on Standard in SQL Server 2019 with Software Assurance + Azure Arc (uncommon).

> **Web Edition:** Licensed for web-facing workloads only. Not suitable for ERP/CRM/internal line-of-business use. Cannot host AG primary replicas in most configurations.

---

## Edition UPGRADE (lower → higher)

Example: Web → Standard, Standard → Enterprise.

An in-place edition upgrade is supported by SQL Server setup, requires no service restart, and takes 5–15 minutes. No data is moved — only the binaries change.

### Step 1 — Confirm you have the target edition licence and product key

```cmd
REM Verify your product key before starting
REM Enterprise: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
REM Standard:   XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
```

### Step 2 — Run setup.exe for edition upgrade

```cmd
REM From the SQL Server installation media (match the version currently installed):
Setup.exe /ACTION=EditionUpgrade
          /INSTANCENAME=MSSQLSERVER
          /PID=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
          /IAcceptSQLServerLicenseTerms
          /INDICATEPROGRESS
```

For named instances replace `/INSTANCENAME=MSSQLSERVER` with `/INSTANCENAME=YourInstanceName`.

### Step 3 — Verify the upgrade

```sql
SELECT CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS edition;
-- Should now show: Enterprise Edition (64-bit) or Standard Edition (64-bit)
```

### Step 4 — Enable newly available features (Enterprise upgrade only)

After upgrading from Standard to Enterprise, features are unlocked but not automatically configured. Plan which features you want to enable:

- **Resource Governor:** `ALTER RESOURCE GOVERNOR RECONFIGURE;`
- **Online index rebuilds:** Modify maintenance plans to use `REBUILD WITH (ONLINE = ON)`
- **AG readable secondaries:** Reconfigure AG replicas if applicable

---

## Edition DOWNGRADE (higher → lower)

Example: Enterprise → Standard, Standard → Web.

**There is no supported in-place edition downgrade.** SQL Server setup does not provide a downgrade path. Your options are:

1. **Side-by-side migration** (recommended) — install the lower edition on a new server, migrate databases
2. **Uninstall + reinstall** — loses all configuration and is essentially a rebuild

**Always use option 1 in production.** The side-by-side approach follows [RUNBOOK-Standalone.md](RUNBOOK-Standalone.md) with the edition feature audit as an additional prerequisite.

### Phase 0 — Feature audit (mandatory before downgrade)

```powershell
.\powershell\migration\Get-EditionFeatureUsage.ps1 -ServerInstance PROD01
```

Or directly:

```powershell
.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\migration\Get-EditionFeatureUsage.sql `
    -ServerInstance PROD01 `
    -OutputFormat Csv `
    -OutputPath output-files\migration\edition-features-PROD01.csv
```

**Review every row where `blocks_downgrade = YES` or `WARN`.** These must be resolved before migration or the databases will not function correctly on the lower edition.

### Resolving each blocker

#### TDE (blocks_downgrade: YES)

Standard Edition cannot open TDE-encrypted databases. **You must remove TDE before migration.**

```sql
-- 1. Disable TDE encryption (starts decryption — takes time proportional to DB size)
ALTER DATABASE [dbname] SET ENCRYPTION OFF;

-- 2. Monitor decryption progress
SELECT DB_NAME(database_id) AS db, encryption_state_desc, percent_complete
FROM sys.dm_database_encryption_keys;

-- 3. After encryption_state = 1 (unencrypted):
USE [dbname];
DROP DATABASE ENCRYPTION KEY;

-- 4. Optionally drop the certificate from master if no longer needed
-- (only if no other databases use it)
```

> **Decryption time:** Allow 1–8 hours per TB of data. Schedule this well in advance of the migration window.

#### Database Snapshots (blocks_downgrade: WARN)

Standard Edition cannot create snapshots. Existing snapshots on the source do not migrate — they are skipped by backup/restore. No action required unless applications depend on snapshot-based reads.

```sql
-- Review existing snapshots
SELECT name, source_database_id, create_date FROM sys.databases WHERE source_database_id IS NOT NULL;

-- Drop snapshots when ready (backup will skip them automatically)
DROP DATABASE [snapshot_name];
```

#### Resource Governor (blocks_downgrade: WARN)

Resource Governor configuration lives in msdb and does not affect database files or restores. After migration to Standard, Resource Governor exists in the catalog but does nothing.

```sql
-- Disable before migration (optional — it just won't function on Standard)
ALTER RESOURCE GOVERNOR DISABLE;

-- Or document the configuration for reference
SELECT *
FROM sys.resource_governor_resource_pools
WHERE name NOT IN ('default', 'internal');
```

#### AG Readable Secondaries (blocks_downgrade: YES)

Standard Basic AG does not support readable secondaries. Applications using read-offload must be redirected.

```sql
-- Review which AGs have readable secondaries configured
SELECT ag.name, ar.replica_server_name, ar.secondary_role_allow_connections_desc
FROM sys.availability_replicas ar
INNER JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
WHERE ar.secondary_role_allow_connections > 0;
```

Before migration, redirect read-scale traffic to the primary, or implement a separate read replica strategy (log shipping, Query Store, etc.).

#### AG with multiple databases (blocks_downgrade: YES for Standard Basic AG)

Standard Basic AG supports exactly 1 database per AG. If your AGs have multiple databases, you must split them before migration.

```sql
-- Check databases per AG
SELECT ag.name, COUNT(*) AS db_count
FROM sys.availability_databases_cluster adc
INNER JOIN sys.availability_groups ag ON adc.group_id = ag.group_id
GROUP BY ag.name;
```

To split: remove extra databases from the AG, create separate AGs for each database.

#### Online Index Operations

Cannot be detected from static metadata. Review all maintenance plans and SQL Agent jobs for `REBUILD WITH (ONLINE = ON)`.

```sql
-- Search agent job steps for ONLINE = ON
SELECT j.name AS job_name, s.step_name, s.command
FROM msdb.dbo.sysjobsteps s
INNER JOIN msdb.dbo.sysjobs j ON s.job_id = j.job_id
WHERE s.command LIKE '%ONLINE%=% ON%';
```

Change any `REBUILD WITH (ONLINE = ON)` to `REBUILD WITH (ONLINE = OFF)` or replace with `REORGANIZE`.

### Phase 1 onwards — Side-by-side migration

After all blockers from the feature audit are resolved, follow **[RUNBOOK-Standalone.md](RUNBOOK-Standalone.md)** using the **Standard Edition** (or Web Edition) install on the target server.

---

## Web Edition specific constraints

Web Edition is licensed for hosting web applications and is not intended for general-purpose enterprise use. Key limitations:

| Constraint | Detail |
|-----------|--------|
| AG Primary | Cannot be a primary replica (can be secondary in some configurations) |
| HADR | Limited high availability options |
| RAM | Capped at OS max but licensed for web workloads only |
| CPU | Licensed for up to 4 sockets |
| Upgrade target | Can upgrade to Standard or Enterprise in-place |

**Migrating FROM Web Edition:** Standard migration runbook applies. Web Edition databases (no TDE, no snapshots, no Resource Governor) have no blockers for restore to Standard or Enterprise.

**Migrating TO Web Edition:** Ensure the source has no features not available in Web Edition. Run `Get-EditionFeatureUsage.sql` — anything that blocks Standard will also block Web.

---

## Quick checklist — downgrade

- [ ] `Get-EditionFeatureUsage.sql` run — all blockers resolved
- [ ] TDE removed from all databases (if applicable) — decryption complete
- [ ] Applications redirected away from readable secondaries (if applicable)
- [ ] AG multi-DB groups split into single-DB AGs (if applicable)
- [ ] Maintenance plans updated to remove ONLINE index rebuilds
- [ ] Side-by-side migration runbook executed (`RUNBOOK-Standalone.md`)
- [ ] Post-migration validation passed (`Get-PostMigrationValidation.sql`)
- [ ] DNS cutover completed

---

## Script quick-reference

| Script | When to run |
|--------|------------|
| `Get-EditionFeatureUsage.ps1` | Before downgrade — mandatory |
| `Invoke-MigrationPreFlightCheck.ps1` | Before migration window |
| `RUNBOOK-Standalone.md` | Full migration procedure (for downgrades) |
| `Get-LinkedServerSecurity.sql` | Review if downgrading linked server auth models |
