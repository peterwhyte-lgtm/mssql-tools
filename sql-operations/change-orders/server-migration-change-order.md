# Change Order — SQL Server Hardware / VM Migration

> **Instructions:** Complete all fields before CAB submission.
> Attach assessment output from `Invoke-PreMigrationAssessment.ps1` and restore test evidence.

---

## 1. Change Metadata

| Field                   | Value |
|-------------------------|-------|
| Change Request Number*  | `[CR-XXXXX]` |
| Change Type*            | `[ ] Standard  [ ] Normal` |
| Risk Rating*            | `[ ] LOW  [ ] MEDIUM  [ ] HIGH` |
| Requested by*           | `[Name, Team]` |
| Technical lead*         | `[DBA Name]` |
| Change manager          | `[Name]` |

**Change Window***

| | Value |
|-|-------|
| Start date/time   | `[YYYY-MM-DD HH:MM]` |
| End date/time     | `[YYYY-MM-DD HH:MM]` |
| Rollback deadline | `[YYYY-MM-DD HH:MM]` |
| Estimated duration | `[X hours]` |
| Rollback duration  | `[X minutes]` — flip DNS/connection strings back to source |

---

## 2. Change Summary

```
SQL Server [version] on [SourceServer] is being migrated to [TargetServer].
SQL Server version on target: [same / upgraded to X]

Migration method: [ ] Backup/restore  [ ] Log shipping cutover  [ ] Detach/attach

Databases being migrated: [Count] databases, [X GB] total data
```

**Reason for migration:**
```
[ ] Hardware refresh / end of life
[ ] VM infrastructure migration
[ ] Data centre relocation
[ ] Cloud migration (on-prem to Azure VM)
[ ] Other: ___________
```

---

## 3. Risk Assessment

| Risk | Mitigation |
|------|------------|
| Backup corruption prevents restore | Backup restore tested in non-prod prior to window |
| Application connectivity fails after DNS flip | App team available; DNS flip is reversible within minutes |
| SQL login SID mismatch — orphaned users | Login script with SID preservation prepared and tested |
| Jobs fail due to hardcoded server name references | Jobs reviewed and tested on non-prod target |
| Performance regression on new hardware | Pre/post baseline captured; source server kept available through rollback deadline |
| Linked server connectivity fails on new server | Linked servers documented; test script prepared |

**Overall risk rating:** `[ ] LOW  [ ] MEDIUM  [ ] HIGH`

---

## 4. Pre-Change Validation (Go / No-Go)

| # | Check | Pass Criteria | Status |
|---|-------|---------------|--------|
| 1 | Risk assessment — zero HIGH findings unresolved | `risk-assessment.csv` clean | `[ ] PASS  [ ] FAIL` |
| 2 | Restore tested in non-prod | `DBCC CHECKDB` clean on restored copy | `[ ] PASS  [ ] FAIL` |
| 3 | Login script tested | All logins created without errors; no orphaned users | `[ ] PASS  [ ] FAIL` |
| 4 | Jobs tested on target | Critical jobs ran successfully in non-prod | `[ ] PASS  [ ] FAIL` |
| 5 | Application connectivity tested | App confirmed working against restored database | `[ ] PASS  [ ] FAIL` |
| 6 | Final backup scheduled | Full backup to complete < 2 hours before window | `[ ] PASS  [ ] FAIL` |
| 7 | Pre-baseline captured | `Export-MigrationBaseline.ps1 -Label pre` output saved | `[ ] PASS  [ ] FAIL` |
| 8 | DNS alias / connection string change plan confirmed | DNS admin / app owner available during window | `[ ] PASS  [ ] FAIL` |
| 9 | Change approved | CAB approval on record | `[ ] PASS  [ ] FAIL` |

---

## 5. Implementation Steps

| Step | Action | Est. Time | Actual Start |
|------|--------|-----------|--------------|
| 1 | Notify application teams — migration beginning | 5 min | |
| 2 | Stop SQL Server Agent on source | 2 min | |
| 3 | Take final full backup of all user databases | `[X min]` | |
| 4 | Drain active sessions | 5 min | |
| 5 | Restore databases on target server WITH RECOVERY | `[X min]` | |
| 6 | Run login script on target | 10 min | |
| 7 | Fix orphaned users — `sp_change_users_login` on each database | 10 min | |
| 8 | Restore SQL Agent jobs, operators, alerts | 15 min | |
| 9 | Configure instance settings (max memory, MAXDOP, TF) | 15 min | |
| 10 | Recreate linked servers | 10 min | |
| 11 | Flip DNS alias or update application connection strings | 5 min | |
| 12 | Confirm application connectivity | 10 min | |
| 13 | Run post-migration validation checks | 20 min | |
| 14 | Capture post-migration baseline | 10 min | |
| 15 | Application owner sign-off | 10 min | |
| 16 | Notify stakeholders — migration complete | 5 min | |

---

## 6. Post-Change Validation

| Check | Pass Criteria |
|-------|---------------|
| All databases ONLINE | `SELECT name, state_desc FROM sys.databases WHERE state <> 0` = 0 rows |
| Application connectivity | Application owner confirms: ___________________________ |
| Jobs present | All expected jobs present in SQL Agent |
| Backup scheduled | `Get-BackupCoverage.sql` — next backup scheduled |
| Error log clean | `Get-RecentErrorLogEntries.sql` — no unexpected errors |
| Source server stopped | SQL Server service stopped on source (prevents reconnection) |

---

## 7. Rollback Plan

**Rollback deadline:** `[YYYY-MM-DD HH:MM]`
**Rollback decision owner:** `[Name]`

**Steps:**

| Step | Action |
|------|--------|
| 1 | Flip DNS alias or connection strings back to source server |
| 2 | Restart SQL Server Agent on source server |
| 3 | Confirm application reconnects to source |
| 4 | Notify stakeholders — rollback complete |
| 5 | Raise post-incident review |

> **Critical:** Source server SQL Server service must NOT be stopped until rollback deadline has passed and sign-off is complete.

---

## 8. Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Technical lead (DBA) | | | |
| Application owner | | | |
| Change manager / CAB | | | |
