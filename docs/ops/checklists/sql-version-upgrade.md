# SQL Server Version Upgrade Checklist

Use for: in-place upgrades and side-by-side migrations to a newer SQL Server version.
Change order template: `../change-orders/sql-server-upgrade-change-order.md`

---

## Pre-Migration — 72 Hours Before

### Assessment

- [ ] Run `Invoke-PreMigrationAssessment.ps1` against source server — save output folder path
- [ ] All **HIGH** findings in `risk-assessment.csv` resolved or formally accepted in change order
- [ ] `deprecated-features.csv` reviewed — all flagged features tested against target version in non-prod
- [ ] `compat-level-audit.csv` reviewed — compat level upgrade plan documented

### Backups

- [ ] All user databases have a full backup completed within the last 24 hours
- [ ] Backup chain verified: full + differential + log (if FULL recovery model)
- [ ] Restore tested on non-prod — at least one database restored and `DBCC CHECKDB` passed
- [ ] Backup storage accessible and sufficient for an additional full backup set

### Environment

- [ ] Target SQL Server version and edition confirmed (Standard vs Enterprise — check feature usage)
- [ ] Target server OS and hardware meet SQL Server version requirements
- [ ] Service accounts documented (SQL Server, SQL Agent, SSAS, SSIS if applicable)
- [ ] SQL Server instance configuration documented: max server memory, MAXDOP, cost threshold, TF settings
- [ ] Windows Firewall rules for SQL ports documented
- [ ] Linked servers documented — connectivity tested from equivalent non-prod server

### Logins and Security

- [ ] `login-audit.csv` reviewed — all SQL logins to migrate identified
- [ ] `Generate-LoginScript.ps1` output reviewed and ready to run on target
- [ ] Windows logins (AD accounts/groups) confirmed accessible from target server's domain/trust
- [ ] `sa` password documented (stored in vault) or reset plan in place

### Jobs and Agents

- [ ] SQL Agent jobs reviewed — hardcoded server names or paths identified and updated
- [ ] SQL Agent operators and alerts documented
- [ ] Job schedules documented — first run times after migration noted

### Application

- [ ] Application owner sign-off obtained
- [ ] Application connectivity test plan confirmed (test query and expected result)
- [ ] Application team available during migration window for connectivity confirmation

### Change Management

- [ ] Change order approved (CAB or equivalent)
- [ ] Maintenance window confirmed: `Start: ___________  End: ___________`
- [ ] Rollback deadline confirmed (must be within maintenance window): `___________`
- [ ] On-call DBA cover confirmed for 24 hours post-migration
- [ ] Monitoring team notified of migration window

---

## Pre-Migration — 24 Hours Before

- [ ] Non-prod migration completed successfully — test evidence attached to change order
- [ ] Final backup confirmed scheduled to run before migration window
- [ ] Rollback scripts staged and accessible (not on the server being migrated)
- [ ] `Export-MigrationBaseline.ps1 -Label pre` run and output folder noted: `___________`
- [ ] All stakeholders confirmed for migration start notification

---

## Migration Day — Before Start

- [ ] Maintenance window confirmed active
- [ ] Confirm source: `SELECT @@VERSION` — record version string: `___________`
- [ ] Confirm no databases in non-ONLINE state: `SELECT name, state_desc FROM sys.databases WHERE state <> 0` — result: 0 rows
- [ ] Run final full backup of ALL user databases — record completion time: `___________`
- [ ] Drain or kill active sessions (confirm with application team): `EXEC sp_who2`
- [ ] SQL Server Agent stopped (prevents jobs firing during migration)
- [ ] Notify application teams: migration starting now
- [ ] All approvers and contacts available and contactable

---

## Execution — Side-by-Side Migration (Recommended for Major Version Jumps)

- [ ] Restore all user databases to target instance — record start time: `___________`
- [ ] All databases restored in NORECOVERY or RECOVERY as appropriate
- [ ] Run login script on target — confirm no errors
- [ ] Fix orphaned users in each restored database: `EXEC sp_change_users_login 'Report'` — resolve any rows
- [ ] Restore SQL Agent jobs, operators, and alerts on target
- [ ] Configure instance settings on target to match source (max server memory, MAXDOP, TF)
- [ ] Create or update linked server definitions on target
- [ ] Point application connection string(s) to new instance (DNS alias flip or config change)

## Execution — In-Place Upgrade

- [ ] SQL Server Agent stopped — confirm: `SELECT status_desc FROM sys.dm_server_services WHERE servicename LIKE '%Agent%'`
- [ ] SQL Server setup launched — record start time: `___________`
- [ ] Setup completed without errors — record end time: `___________`
- [ ] SQL Server service started: confirm in Services or: `SELECT status_desc FROM sys.dm_server_services WHERE servicename LIKE '%SQL Server%'`

---

## Post-Migration Validation — First 30 Minutes

- [ ] `SELECT @@VERSION` — confirms target version: `___________`
- [ ] `SELECT name, state_desc FROM sys.databases WHERE state <> 0` — confirms 0 results
- [ ] `Get-DatabaseHealth.sql` — all databases ONLINE, no suspect pages, no auto-shrink on
- [ ] `Get-AvailabilityGroupReplicaState.sql` — AG replicas SYNCHRONIZED (if applicable)
- [ ] `Get-SqlAgentJobOverview.sql` — jobs present and enabled
- [ ] `Get-BackupCoverage.sql` — backup schedule will fire at next scheduled time
- [ ] Application connectivity test passed — confirm with application team: `___________`
- [ ] Linked servers resolve from new instance: `EXEC sp_testlinkedserver N'<linked_server_name>'`
- [ ] SQL Server Agent restarted
- [ ] `Export-MigrationBaseline.ps1 -Label post` run — compare against pre-baseline

---

## Post-Migration Validation — First 24 Hours

- [ ] SQL Agent jobs ran at their next scheduled time without failure
- [ ] Backup job ran successfully: `Get-BackupCoverage.sql`
- [ ] Error log clean: `Get-RecentErrorLogEntries.sql`
- [ ] Performance within expected range: `Get-WaitStatistics.sql` — compare against pre-migration baseline
- [ ] Compat level upgrade applied (if planned): `ALTER DATABASE [dbname] SET COMPATIBILITY_LEVEL = xxx`
- [ ] Statistics updated: `EXEC sp_updatestats` or full `UPDATE STATISTICS` run (after compat level change)
- [ ] `DBCC CHECKDB` scheduled for all migrated databases within 48 hours

---

## Sign-Off

| Role                  | Name | Signature | Date |
|-----------------------|------|-----------|------|
| DBA (lead)            |      |           |      |
| Application owner     |      |           |      |
| Change manager        |      |           |      |

---

## Rollback Criteria

**Initiate rollback immediately if ANY of the following:**
- SQL Server setup fails or service does not start after upgrade
- Any user database fails to come ONLINE within 15 minutes of migration start
- Application cannot connect within 20 minutes of cutover
- AG secondary cannot synchronise within 30 minutes of cutover
- Data loss detected (row count mismatch on critical tables)
- Rollback deadline reached and validation is incomplete

**Rollback decision owner:** `___________`
**Rollback procedure:** `../rollback/migration-rollback-playbook.md`
