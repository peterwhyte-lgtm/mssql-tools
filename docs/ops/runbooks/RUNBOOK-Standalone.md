# SQL Server Standalone Migration Runbook

Migrating a standalone SQL Server instance to new hardware or a new VM. Covers the DNS-cutover approach — applications keep their existing connection strings unchanged.

**Applies to:** SQL Server 2016–2022 · Web / Standard / Enterprise Edition · Windows Server

---

## Scope and assumptions

| Item | Value |
|------|-------|
| Number of servers | 50 (this runbook covers one at a time) |
| Databases per server | ~3 000 |
| Migration method | Backup → Transfer → Restore |
| Cutover method | DNS rename / A-record swap |
| Downtime | 1–4 hours per server (restore time dominates) |
| Source edition | SQL Server Web Edition |
| Target edition | SQL Server Web Edition (or higher) |

> **Web Edition note.** Web Edition cannot be an Availability Group primary replica (Standard or higher required for the primary). For standalone-to-standalone migrations, this is not a constraint.

---

## Before you start — per-server checklist

- [ ] SQL Server installed and service running on target
- [ ] Same collation as source (`SELECT SERVERPROPERTY('Collation')`)
- [ ] Target drives created: data volume, log volume, TempDB volume, backup volume
- [ ] SQL Server service account is a domain account (needed for SPN management)
- [ ] Backup share accessible from both source and target
- [ ] Port 1433 open between target and any application servers
- [ ] DNS write access confirmed (to update A record at cutover)
- [ ] Maintenance window agreed with application teams

---

## Phase 0 — Pre-migration assessment (run on source, days before window)

**Goal:** identify blockers before the migration window starts.

```powershell
# From the repo root
.\powershell\migration\Invoke-PreMigrationAssessment.ps1 -ServerInstance PROD01
```

**Output folder:** `output-files\migration\assessment\PROD01-<timestamp>\`

| File | Review for |
|------|-----------|
| `risk-assessment.csv` | Any HIGH findings — resolve before proceeding |
| `deprecated-features.csv` | Features in use that target version may not support |
| `compat-level-audit.csv` | Databases running below native compat level — plan upgrade |
| `login-audit.csv` | Logins that need manual attention (e.g. mapped to certificates) |
| `backup-coverage.csv` | Confirm backup chain is complete before relying on restores |
| `linked-servers.csv` | Inventory of linked servers to recreate on target |
| `database-files.csv` | Source data/log paths — needed for WITH MOVE parameters |
| `database-sizes.csv` | Total data size — estimate transfer and restore time |

**Go/no-go:** Address all HIGH findings in `risk-assessment.csv` before booking the window.

---

## Phase 1 — Prepare the target server (before the window)

### 1.1 Match sp_configure settings

Run on source, save output, then apply on target:

```sql
-- On source — capture key configuration
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)',
    'min server memory (MB)',
    'max degree of parallelism',
    'cost threshold for parallelism',
    'optimize for ad hoc workloads',
    'backup compression default',
    'remote login timeout (s)',
    'remote query timeout (s)',
    'backup checksum default'
)
ORDER BY name;
```

Apply each on target using `EXEC sp_configure 'name', value; RECONFIGURE WITH OVERRIDE;`

### 1.2 Configure TempDB on target

TempDB setup must be done before users connect. Best practice: one data file per logical CPU core, up to 8.

```sql
-- Check how many TempDB files the target has
SELECT file_id, name, physical_name, size/128 AS size_mb
FROM sys.master_files WHERE database_id = 2;
```

Add files to match the planned count, then make all files equal size with fixed-MB autogrowth.

### 1.3 Create backup share folder

Ensure the UNC path `\\BACKUP-SERVER\SQL-Backups` (or local path) exists and the SQL Server service account has read/write access.

### 1.4 Verify firewall and connectivity

```powershell
# From target — confirm source is reachable on 1433
Test-NetConnection -ComputerName PROD01 -Port 1433
```

---

## Phase 2 — Generate all migration artifacts (run on source, before window)

One command generates everything needed for the migration:

```powershell
.\powershell\migration\Invoke-MigrationExport.ps1 -ServerInstance PROD01
```

**Output folder:** `output-files\migration\export\PROD01-<timestamp>\`

| File | What it is |
|------|-----------|
| `00-pre-migration-assessment\` | CSV inventory snapshots |
| `logins.sql` | `CREATE LOGIN` with original SIDs and hashed passwords |
| `agent-jobs.sql` | `sp_add_job` DDL for all SQL Agent jobs |
| `linked-servers.sql` | `sp_addlinkedserver` DDL (passwords redacted — see note) |
| `user-mappings.sql` | Per-database `ALTER USER` mappings |
| `full-backup.sql` | `BACKUP DATABASE` for all online databases |
| `restore-with-move.sql` | `RESTORE DATABASE ... WITH MOVE` |
| `validation-baseline.csv` | Source server counts for post-migration diff |

> **Linked server passwords.** Any mapping using stored credentials (HIGH risk in `Get-LinkedServerSecurity.sql`) shows `ENTER_PASSWORD_HERE`. You must enter these manually on the target after running `linked-servers.sql`.

---

## Phase 3 — Take backups (during the window, on source)

### 3.1 Set the backup path

Open `full-backup.sql`. Change `@BackupPath` at the top:

```sql
DECLARE @BackupPath nvarchar(260) = N'\\BACKUP-SERVER\SQL-Backups';
```

### 3.2 Run the backup script on source

For 3 000 databases this will take hours — start as early in the window as possible.

```powershell
# Monitor progress in a second window
SELECT session_id, percent_complete, estimated_completion_time,
       command, DB_NAME(database_id) AS database_name
FROM sys.dm_exec_requests
WHERE command LIKE 'BACKUP%';
```

### 3.3 Note the timestamp

The backup filenames are `<dbname>_FULL_<timestamp>.bak`. Copy the timestamp portion — you will need it for `restore-with-move.sql`.

---

## Phase 4 — Restore databases on target

### 4.1 Configure the restore script

Open `restore-with-move.sql` and set the four path variables at the top:

```sql
DECLARE @BackupPath    nvarchar(260) = N'\\BACKUP-SERVER\SQL-Backups';
DECLARE @OldDataRoot   nvarchar(260) = N'E:\SQLData';   -- source data path prefix
DECLARE @NewDataRoot   nvarchar(260) = N'D:\SQLData';   -- target data path prefix
DECLARE @OldLogRoot    nvarchar(260) = N'L:\SQLLogs';
DECLARE @NewLogRoot    nvarchar(260) = N'L:\SQLLogs';
```

Also set `@ts` in the generated output to the backup timestamp from Phase 3.3.

> **Same drive layout?** If source and target have identical drive paths, use `Generate-RestoreScript.sql` without WITH MOVE instead — it is simpler and requires fewer parameters.

### 4.2 Run the restore script on target

Execute the generated output on the target server. Monitor progress:

```sql
SELECT session_id, percent_complete, estimated_completion_time,
       command, DB_NAME(database_id) AS database_name
FROM sys.dm_exec_requests
WHERE command LIKE 'RESTORE%';
```

### 4.3 Check all databases came online

```sql
SELECT name, state_desc, recovery_model_desc
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
```

Any database in `RESTORING` or `RECOVERY_PENDING` state needs investigation before proceeding.

---

## Phase 5 — Migrate server objects (on target)

Run these scripts on the target in order.

### 5.1 Create logins

```sql
-- Run logins.sql on TARGET
-- Logins are created with their original SIDs and hashed passwords.
-- SQL-authenticated database users will automatically map back to their login
-- because the SID is preserved.
```

### 5.2 Add SQL Agent jobs

```sql
-- Run agent-jobs.sql on TARGET
-- Review @owner_login_name in the output — the login must exist on target.
-- Job owners default to 'sa' if the original owner login is missing.
```

### 5.3 Add linked servers

```sql
-- Run linked-servers.sql on TARGET
-- Search for ENTER_PASSWORD_HERE and replace with actual remote passwords.
-- Test each linked server after creation:
SELECT * FROM OPENQUERY([LINKEDSRVNAME], 'SELECT 1 AS test');
```

---

## Phase 6 — Fix orphaned users and validate

### 6.1 Run orphaned user fix

```sql
-- On TARGET — generates ALTER USER statements
-- Review the output, then execute:
```

```powershell
# Or run directly from the repo
.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\migration\Fix-OrphanedUsers.sql `
    -ServerInstance TARGET01 `
    -OutputFormat DdlFile `
    -OutputPath output-files\migration\export\fix-orphans.sql
```

### 6.2 Restore compatibility levels (optional)

If you want to upgrade compatibility levels at migration time:

```sql
-- Review compat-level-audit.csv from Phase 0
-- Upgrade one database at a time and test the application before mass-upgrading
ALTER DATABASE [dbname] SET COMPATIBILITY_LEVEL = 150; -- SQL 2019
```

### 6.3 Run validation comparison

```sql
-- Run on TARGET:
-- sql\migration\Get-PostMigrationValidation.sql
-- Compare output against validation-baseline.csv from Phase 2
```

Critical columns to match:
- `user_database_count` — must match exactly
- `databases_not_online` — must be "All ONLINE"
- `total_login_count` — should be equal (or higher if you added new logins)
- `linked_server_count` — must match

**Do not proceed to cutover if `databases_not_online` shows any count > 0.**

---

## Phase 7 — DNS cutover

The DNS cutover is the moment of actual downtime. Keep applications disconnected until DNS propagates and connections to the old name resolve to the new server.

### 7.1 Confirm all applications are disconnected from source

```sql
-- On SOURCE — confirm no active sessions from application servers
SELECT login_name, host_name, program_name, COUNT(*) AS sessions
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name, host_name, program_name
ORDER BY sessions DESC;
```

### 7.2 Update the DNS A record

```powershell
# On DNS server — update A record to point old name to new IP
# (adjust zone name and record name to your environment)
$zone     = 'corp.example.com'
$record   = 'PROD01'          # old server name
$newIP    = '10.0.1.50'       # new server IP

$old = Get-DnsServerResourceRecord -ZoneName $zone -Name $record -RRType A
$new = $old.Clone()
$new.RecordData.IPv4Address = $newIP

Set-DnsServerResourceRecord -ZoneName $zone -OldInputObject $old -NewInputObject $new
```

Set TTL to 60 seconds before the window so the change propagates quickly. Restore a longer TTL (e.g. 300s) after confirmation.

### 7.3 Update SQL Server SPNs

If applications use Windows Authentication (Kerberos), the SPN must be moved from the old service account to the new one. Run on a domain controller or machine with AD admin rights:

```cmd
REM Remove SPNs from OLD service account
setspn -D MSSQLSvc/PROD01:1433          DOMAIN\OldSqlSvcAcct
setspn -D MSSQLSvc/PROD01.corp.example.com:1433 DOMAIN\OldSqlSvcAcct

REM Add SPNs to NEW service account
setspn -A MSSQLSvc/PROD01:1433          DOMAIN\NewSqlSvcAcct
setspn -A MSSQLSvc/PROD01.corp.example.com:1433 DOMAIN\NewSqlSvcAcct

REM For named instances replace port with instance name:
REM setspn -A MSSQLSvc/PROD01:INSTANCENAME DOMAIN\NewSqlSvcAcct

REM Verify
setspn -L DOMAIN\NewSqlSvcAcct
```

### 7.4 Flush DNS on application servers (if TTL is not yet expired)

```cmd
ipconfig /flushdns
```

---

## Phase 8 — Post-cutover validation

### 8.1 Confirm applications can connect

Ask each application team to confirm connectivity and run a basic functional test. Look for errors in the SQL Server error log on the target:

```sql
EXEC xp_readerrorlog 0, 1, N'Error', NULL, NULL, NULL, N'desc';
```

### 8.2 Check for failed logins (wrong SPN or missing logins)

```sql
-- Target server error log — watch for login failed messages
EXEC xp_readerrorlog 0, 1, N'Login failed', NULL, NULL, NULL, N'desc';
```

### 8.3 Run health check on target

```powershell
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance TARGET01
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

---

## Rollback procedure

If cutover fails, revert DNS within the maintenance window:

```powershell
# Revert DNS A record to original IP
$old = Get-DnsServerResourceRecord -ZoneName $zone -Name $record -RRType A
$new = $old.Clone()
$new.RecordData.IPv4Address = '10.0.1.40'   # original IP
Set-DnsServerResourceRecord -ZoneName $zone -OldInputObject $old -NewInputObject $new
```

Revert SPNs to the old service account (reverse the setspn commands from Phase 7.3).

Applications reconnect to the source server automatically once DNS propagates.

> Source databases remain intact — the backup/restore approach is fully non-destructive to the source.

---

## Timing estimates

| Phase | Time estimate | Notes |
|-------|---------------|-------|
| Phase 0 — Assessment | 15 min | Automated |
| Phase 1 — Prepare target | 2–4 hours | Manual — do before window |
| Phase 2 — Generate artifacts | 10–20 min | Depends on job/login count |
| Phase 3 — Backups | 2–8 hours | Depends on total data size |
| Phase 4 — Restores | 2–8 hours | Parallel to backup transfer |
| Phase 5 — Server objects | 15–30 min | Automated |
| Phase 6 — Validation | 15 min | Automated + manual review |
| Phase 7 — DNS cutover | 5–15 min | Downtime window |
| Phase 8 — Post-cutover | 30 min | App team verification |

**Total maintenance window:** Phase 7 + Phase 8 ≈ 30–45 minutes of actual downtime. Phases 3–6 happen in parallel during the broader migration window.

---

## Script quick-reference

| Script | Purpose | Run on |
|--------|---------|--------|
| `Invoke-PreMigrationAssessment.ps1` | Full source assessment | Source |
| `Invoke-MigrationExport.ps1` | Generate all migration artifacts | Source |
| `Generate-FullBackupScript.sql` | BACKUP all user databases | Source |
| `Generate-LoginScript.sql` | CREATE LOGIN with SIDs | Source → execute on Target |
| `Generate-AgentJobScript.sql` | sp_add_job DDL | Source → execute on Target |
| `Generate-LinkedServerScript.sql` | sp_addlinkedserver DDL | Source → execute on Target |
| `Generate-UserMappingScript.sql` | ALTER USER per database | Source → execute on Target |
| `Generate-RestoreWithMoveScript.sql` | RESTORE with path remapping | Source → execute on Target |
| `Fix-OrphanedUsers.sql` | Re-map orphaned DB users | Target |
| `Get-PostMigrationValidation.sql` | Source vs target count diff | Both servers |
| `Invoke-HealthCheckCollection.ps1` | Full health check on target | Target |
