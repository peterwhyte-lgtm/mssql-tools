# SQL Server Version Upgrade Runbook

Upgrading SQL Server from one major version to another (e.g. SQL 2016 → SQL 2019, SQL 2019 → SQL 2022).

**Applies to:** SQL Server 2012–2022 · All editions · Windows Server

---

## Choose your upgrade approach

| Approach | When to use | Downtime |
|----------|------------|---------|
| **Side-by-side** (new server) | Preferred for production · Testable before cutover · Easy rollback | Cutover window only (DNS swap) |
| **In-place** (same server) | Test/dev environments · Cannot justify new hardware | Full downtime until upgraded |

For 50-server migrations with 3 000+ databases: **always use side-by-side**. You can run the new server in parallel, validate, and roll back cheaply. In-place on 50 servers is a one-way door.

---

## Supported direct upgrade paths

A **direct in-place upgrade** means setup.exe can upgrade straight from version A to version B without an intermediate step.

| Source version | Direct targets |
|---------------|---------------|
| SQL Server 2012 | 2016, 2017, 2019, 2022 |
| SQL Server 2014 | 2016, 2017, 2019, 2022 |
| SQL Server 2016 | 2019, 2022 |
| SQL Server 2017 | 2019, 2022 |
| SQL Server 2019 | 2022 |
| SQL Server 2008 / 2008 R2 | **Not direct to 2017+** — upgrade to 2014 or 2016 first, or use side-by-side |

> **Backup/restore compatibility:** Databases can only be restored to the **same or newer** SQL Server version. You cannot restore a SQL 2019 backup onto SQL 2017.

---

## Side-by-side upgrade (recommended)

A side-by-side version upgrade is identical to a server migration — you are building a new server with the target SQL Server version and migrating all objects across. Follow **[RUNBOOK-Standalone.md](RUNBOOK-Standalone.md)** for the full procedure.

The only additional steps specific to a version upgrade are:

### Step 1 — Run version upgrade readiness assessment

```powershell
# Run on each source server before scheduling the window
.\powershell\migration\Get-VersionUpgradeReadiness.ps1 -ServerInstance PROD01
```

Also run the deprecated features check:

```powershell
.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\migration\Get-DeprecatedFeaturesInUse.sql `
    -ServerInstance PROD01
```

**Review the output:**
- `compatibility_gap` — databases more than 2 versions behind native compat level need testing
- `upgrade_paths` — confirms whether your source-to-target path is direct
- `review_note` column in configuration result — flags settings that need reconfiguring post-upgrade
- Deprecated features with `usage_count_since_restart > 0` — test the application against the target version's compat level before committing

### Step 2 — Install the new SQL Server version on the target

Install the target SQL Server version using the same edition as the source (or the new edition if changing at the same time — see [RUNBOOK-SqlEditionChange.md](RUNBOOK-SqlEditionChange.md)).

Apply the latest cumulative update for the target version before migration. Check [sqlserverupdates.com](https://sqlserverupdates.com) for the current CU.

### Step 3 — Follow the Standalone Migration Runbook

Complete all phases of [RUNBOOK-Standalone.md](RUNBOOK-Standalone.md). Come back here for the post-restore compatibility level step.

### Step 4 — Compatibility level upgrade (post-restore, pre-cutover)

After databases are restored on the target, they will have their original compatibility level. Do not blindly upgrade all databases at once — test each application against the new compat level first.

```sql
-- On target — check what compat levels databases are running
SELECT name, compatibility_level, state_desc
FROM sys.databases
WHERE database_id > 4
ORDER BY compatibility_level, name;
```

**Compatibility level mapping:**

| SQL Server | Native compat level |
|-----------|-------------------|
| 2022 | 160 |
| 2019 | 150 |
| 2017 | 140 |
| 2016 | 130 |
| 2014 | 120 |
| 2012 | 110 |
| 2008/R2 | 100 |

**Recommended upgrade sequence per database:**

1. Leave databases at their original compat level initially (safe fallback)
2. Test your application against the target version while still at original compat level
3. Raise compat level to the new native level on a test/dev copy
4. Validate query plans and performance (check sys.dm_exec_query_stats for regressions)
5. Raise production compat level during a low-traffic window
6. Enable Query Store on critical databases to capture a pre/post baseline

```sql
-- Upgrade compat level for one database at a time
ALTER DATABASE [dbname] SET COMPATIBILITY_LEVEL = 150;  -- for SQL 2019

-- Enable Query Store to catch plan regressions
ALTER DATABASE [dbname] SET QUERY_STORE = ON;
ALTER DATABASE [dbname] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000
);
```

---

## In-place upgrade procedure

Use only for non-production or when side-by-side is not possible.

### Pre-upgrade checklist

- [ ] Full backup of all user databases and system databases (master, msdb, model)
- [ ] Run `Get-VersionUpgradeReadiness.ps1` and address all HIGH items
- [ ] Run `Get-DeprecatedFeaturesInUse.sql` — resolve or document all deprecated features
- [ ] Confirm backups are restorable (RESTORE VERIFYONLY)
- [ ] Confirm maintenance window is booked and communicated
- [ ] Confirm you can roll back (you cannot downgrade SQL Server in-place)

```powershell
# Take full backups immediately before the upgrade
.\tools\local-sql\Invoke-RepoSql.ps1 `
    -ScriptPath sql\backups\Generate-FullBackupScript.sql `
    -ServerInstance PROD01 `
    -OutputFormat DdlFile `
    -OutputPath output-files\migration\pre-upgrade-backup.sql

# Edit @BackupPath in the output file, then run it
```

### In-place upgrade steps

1. **Stop SQL Server Agent** — prevent jobs from running during upgrade

```sql
-- On source, before starting setup
EXEC msdb.dbo.sp_stop_job @job_name = N'YourJobName';  -- stop individual jobs if needed
```

2. **Run SQL Server setup**

```cmd
REM From the SQL Server installation media:
Setup.exe /ACTION=Upgrade
           /INSTANCENAME=MSSQLSERVER
           /IAcceptSQLServerLicenseTerms
           /UpdateEnabled=1
           /INDICATEPROGRESS
```

Setup preserves:
- Instance name, service account, port
- All user databases
- msdb (SQL Agent jobs, maintenance plans)
- Linked server definitions
- sp_configure values

Setup upgrades:
- SQL Server binaries and engine version
- master, model, msdb system databases (schema updates)
- Resource database

3. **Monitor progress** — setup writes to `%ProgramFiles%\Microsoft SQL Server\...\Setup Bootstrap\Log\`

4. **Post-upgrade validation**

```sql
-- Confirm version upgraded
SELECT @@VERSION;
SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20));

-- Check all databases are ONLINE
SELECT name, state_desc FROM sys.databases ORDER BY database_id;

-- Check for errors in the upgrade log
EXEC xp_readerrorlog 0, 1, N'Error', NULL, NULL, NULL, N'desc';
```

5. **Apply the latest Cumulative Update** for the new version immediately after upgrade.

---

## Post-upgrade validation

Run these checks regardless of in-place or side-by-side approach:

```powershell
# Full health check on the upgraded/new server
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance TARGET01
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

Key things to verify:
- All databases are ONLINE
- SQL Agent jobs are running (check msdb.dbo.sysjobhistory for failures)
- Application teams confirm connectivity and functionality
- Check error log for warnings about deprecated features now being errors
- Run sp_updatestats on each database after compatibility level upgrade

```sql
-- Update statistics after compat level change (can change cardinality estimation)
EXEC sp_updatestats;

-- Rebuild system objects (sometimes needed after major version jump)
EXEC sp_refreshsqlmodule @name = N'<view or proc name>';
```

---

## Rollback procedure

**Side-by-side:** Revert DNS to the source server. The source is untouched.

**In-place:** No direct downgrade path exists. Your only rollback option is restoring the pre-upgrade system database backups (master, msdb, model) and user database backups onto a SQL Server installation of the **previous version**. This is destructive and time-consuming — this is why side-by-side is strongly preferred.

---

## Script quick-reference

| Script | When to run |
|--------|------------|
| `Get-VersionUpgradeReadiness.ps1` | Before booking the window — source server |
| `Get-DeprecatedFeaturesInUse.sql` | Before booking the window — source server |
| `Get-MigrationRiskAssessment.sql` | Before booking the window — source server |
| `Invoke-MigrationPreFlightCheck.ps1` | Day before window — source + target |
| `Generate-FullBackupScript.sql` | Just before upgrade — source |
| `Get-PostMigrationValidation.sql` | After upgrade — compare source and target |
| `Invoke-HealthCheckCollection.ps1` | After upgrade — target |
