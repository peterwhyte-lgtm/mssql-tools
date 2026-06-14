# Server Replacement Checklist

Use for: physical-to-physical, physical-to-VM, or VM-to-VM server replacements.
Covers the backup/restore and log shipping cutover approaches.
Change order template: `../change-orders/server-migration-change-order.md`

---

## Pre-Migration — 72 Hours Before

### Assessment

- [ ] Run `Invoke-PreMigrationAssessment.ps1` against source server — address all HIGH findings
- [ ] `login-audit.csv` reviewed — SQL logins scripted with `Generate-LoginScript.ps1`
- [ ] `backup-coverage.csv` reviewed — all databases have recent full backups
- [ ] `agent-jobs` CSV reviewed — job steps with hardcoded server names updated for new server name
- [ ] Linked servers documented — recreate scripts prepared for new server
- [ ] Startup parameters and trace flags documented
- [ ] `Export-MigrationBaseline.ps1 -Label pre` run — output folder noted: `___________`

### New Server

- [ ] New server has sufficient CPU, RAM, and disk (compare against `os-hardware.csv` from assessment)
- [ ] SQL Server installed on new server (same or newer version/edition)
- [ ] SQL Server patch level confirmed (same as or higher than source)
- [ ] Same collation as source server: `SELECT SERVERPROPERTY('Collation')` — source: `___________`
- [ ] Service accounts created and assigned (SQL Server, SQL Agent)
- [ ] SQL Server service accounts have rights to backup and data file folders
- [ ] Network connectivity confirmed between source and new server (for backup copy or log shipping)
- [ ] New server meets firewall and connectivity requirements for applications

### Application

- [ ] Application team notified and available for connectivity testing
- [ ] DNS alias (CNAME) strategy confirmed: flip alias vs update connection strings
- [ ] Application connection string owner identified and available during cutover

---

## Pre-Migration — 24 Hours Before

- [ ] Test restore completed on new server — at least 1 database restored and `DBCC CHECKDB` passed
- [ ] Login script tested on new server — no errors, logins created with correct SIDs
- [ ] SQL Agent jobs restored to new server — test execution verified in non-prod
- [ ] Instance-level settings configured on new server: max server memory, MAXDOP, linked servers
- [ ] Final full backup confirmed scheduled to run before migration window
- [ ] Rollback plan confirmed and staged

---

## Migration Day — Before Start

- [ ] Maintenance window active and approved
- [ ] `SELECT @@VERSION` on source — record: `___________`
- [ ] `SELECT name, state_desc FROM sys.databases WHERE state <> 0` on source — 0 results expected
- [ ] Application connections drained — confirm with application team: `___________`
- [ ] SQL Server Agent stopped on source
- [ ] Final full backup of ALL user databases completed — record completion time: `___________`

---

## Option A — Backup and Restore Cutover

### Migration

- [ ] Copy backup files to new server (or restore directly from shared backup path)
- [ ] Restore all user databases WITH RECOVERY on new server
- [ ] Record restore start time: `___________`
- [ ] All databases restored — confirm: `SELECT name, state_desc FROM sys.databases WHERE state <> 0` — 0 results
- [ ] Run login script on new server — confirm no errors
- [ ] Fix orphaned database users: run `EXEC sp_change_users_login 'Report'` in each restored database — resolve all rows
- [ ] Restore SQL Agent jobs, operators, and alerts
- [ ] Configure instance settings (max memory, MAXDOP, startup trace flags)
- [ ] Recreate linked servers
- [ ] Flip DNS alias or update application connection strings to new server name

### Post-Cutover Validation

- [ ] `Select @@VERSION` on new server — record: `___________`
- [ ] All databases ONLINE: `SELECT name, state_desc FROM sys.databases WHERE state <> 0` — 0 results
- [ ] Application connectivity confirmed: `___________`
- [ ] SQL Server Agent started on new server
- [ ] Backup job fires on new server at next scheduled time

---

## Option B — Log Shipping Cutover (Minimal Downtime)

### Setup Phase (Days Before)

- [ ] Log shipping configured: source = primary, new server = secondary (STANDBY or NO RECOVERY)
- [ ] Log shipping latency confirmed < 30 seconds during business hours
- [ ] Monitor log shipping status: `SELECT * FROM msdb.dbo.log_shipping_monitor_secondary`
- [ ] Confirm secondary server disk space sufficient for growth during shipping period

### Cutover

- [ ] Application connections drained
- [ ] SQL Server Agent stopped on source (stops log shipping jobs)
- [ ] Take final transaction log backup on source and copy to secondary
- [ ] Restore final log backup on secondary WITH RECOVERY — brings database online
- [ ] Run login script on new server
- [ ] Fix orphaned database users
- [ ] Flip DNS alias or update connection strings
- [ ] Start SQL Server Agent on new server
- [ ] Start backup jobs on new server

### Post-Cutover

- [ ] Application connectivity confirmed: `___________`
- [ ] All databases ONLINE — 0 results from state check
- [ ] Backup job fires at next scheduled time

---

## Post-Migration Validation — All Options

- [ ] `Get-DatabaseHealth.sql` — all databases ONLINE
- [ ] `Get-BackupCoverage.sql` — backup schedule will fire
- [ ] `Get-SqlAgentJobOverview.sql` — jobs present and enabled
- [ ] `Get-RecentErrorLogEntries.sql` — no unexpected errors
- [ ] `Export-MigrationBaseline.ps1 -Label post` — compare against pre-baseline
- [ ] Source server SQL Server service stopped (prevents accidental reconnection)
- [ ] 24-hour monitoring period — confirm jobs ran and backups succeeded

---

## Sign-Off

| Role                  | Name | Signature | Date |
|-----------------------|------|-----------|------|
| DBA (lead)            |      |           |      |
| Application owner     |      |           |      |
| Change manager        |      |           |      |

---

## Rollback Criteria

**Initiate rollback if ANY of the following:**
- Any user database fails to restore (backup corruption — rollback impossible without backup fix)
- Application cannot connect to new server within 20 minutes of cutover
- Data integrity failure detected (`DBCC CHECKDB` with errors)
- Critical SQL Agent job fails on first execution after migration
- Rollback deadline reached and validation incomplete

**Rollback action:** Flip DNS alias or connection strings back to source server; restart SQL Server Agent on source server. Note: rollback is only possible if source server SQL Server service was not shut down.