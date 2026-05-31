# Change Order — SQL Server Version Upgrade

> **Instructions:** Complete all fields before CAB submission. Fields marked `*` are mandatory.
> Attach assessment output from `Invoke-PreMigrationAssessment.ps1` and non-prod test evidence.

---

## 1. Change Metadata

| Field                  | Value |
|------------------------|-------|
| Change Request Number* | `[CR-XXXXX]` |
| Change Type*           | `[ ] Standard  [ ] Normal  [x] Normal` |
| Priority*              | `[ ] Low  [ ] Medium  [ ] High  [ ] Critical` |
| Risk Rating*           | `[ ] LOW  [ ] MEDIUM  [ ] HIGH` |
| Status                 | `[ ] Draft  [ ] Submitted  [ ] Approved  [ ] Closed` |
| Requested by*          | `[Name, Team]` |
| Technical lead*        | `[DBA Name]` |
| Change manager         | `[Name]` |

**Change Window***

| | Value |
|-|-------|
| Start date/time  | `[YYYY-MM-DD HH:MM]` |
| End date/time    | `[YYYY-MM-DD HH:MM]` |
| Rollback deadline | `[YYYY-MM-DD HH:MM]` — rollback must begin by this time if validation is not complete |
| Estimated duration | `[X hours]` |
| Rollback duration  | `[X minutes]` |

---

## 2. Change Summary

**What is changing:**
```
SQL Server version upgrade from [Source Version, e.g., SQL Server 2016 SP3 CU15]
to [Target Version, e.g., SQL Server 2019 CU23] on [Server Name].

Migration approach: [ ] In-place upgrade  [ ] Side-by-side backup/restore

Databases affected: [Count] user databases
Total data size: [X GB]
```

**Business justification:**
```
[Reason for upgrade — e.g., end of extended support, new feature requirement, compliance requirement]
```

**Affected systems:**
```
Source server:  [SERVERNAME\INSTANCENAME]
Target server:  [SERVERNAME\INSTANCENAME]  (side-by-side only)
Applications:   [List application names and owners]
AG name:        [AG name, or N/A]
```

---

## 3. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Database fails to come ONLINE after migration | Low | High | Backup/restore tested in non-prod; rollback to source within deadline |
| Application connectivity failure | Low | High | Connectivity test plan confirmed; application team available during window |
| SQL Agent job failures due to hardcoded paths | Medium | Medium | Jobs reviewed and tested in non-prod; agent jobs disabled during migration |
| Deprecated feature causing application error | Low | Medium | `deprecated-features.csv` reviewed; tested with target compat level in non-prod |
| Login/permission mismatch on target | Low | Medium | Login script with SID preservation prepared and tested |
| Performance regression post-migration | Low | High | Pre/post baseline captured; rollback available within deadline |
| Data loss due to backup gap | Very low | Critical | Final full backup taken immediately before migration; backup verified |

**Overall risk rating:** `[ ] LOW  [ ] MEDIUM  [ ] HIGH`

**Risk justification:**
```
[1-2 sentences explaining the overall risk rating — e.g., "Risk is MEDIUM due to database size
requiring a 4-hour restore window, limiting rollback time. Mitigated by pre-tested backups and
application team availability."]
```

---

## 4. Pre-Change Validation (Go / No-Go)

All items must be **PASS** before migration begins. Any **FAIL** item = do not proceed.

| # | Validation Check | Expected Result | Status |
|---|-----------------|-----------------|--------|
| 1 | `Invoke-PreMigrationAssessment.ps1` — zero HIGH findings unresolved | PASS / risk-assessment.csv clean | `[ ] PASS  [ ] FAIL` |
| 2 | All databases in ONLINE state on source | `SELECT name, state_desc FROM sys.databases WHERE state <> 0` = 0 rows | `[ ] PASS  [ ] FAIL` |
| 3 | Final full backup of all user databases completed | All databases backed up < 2 hours before start | `[ ] PASS  [ ] FAIL` |
| 4 | Backup restore tested in non-prod | `DBCC CHECKDB` on restored copy = no errors | `[ ] PASS  [ ] FAIL` |
| 5 | Login script tested in non-prod | All logins created without SID errors | `[ ] PASS  [ ] FAIL` |
| 6 | Application connectivity test in non-prod | App returns expected results from restored DB | `[ ] PASS  [ ] FAIL` |
| 7 | Non-prod upgrade completed without errors | Setup log clean; no post-upgrade errors | `[ ] PASS  [ ] FAIL` |
| 8 | Pre-migration baseline captured | `Export-MigrationBaseline.ps1 -Label pre` output saved | `[ ] PASS  [ ] FAIL` |
| 9 | AG replicas all SYNCHRONIZED (if applicable) | `Get-AvailabilityGroupReplicaState.sql` — all SYNCHRONIZED | `[ ] PASS  [ ] FAIL` |
| 10 | Change window approved, rollback deadline confirmed | CAB approval on record | `[ ] PASS  [ ] FAIL` |

---

## 5. Implementation Steps

| Step | Action | Est. Time | Actual Start | Notes |
|------|--------|-----------|--------------|-------|
| 1 | Notify application teams — migration beginning | 5 min | | |
| 2 | Stop SQL Server Agent on source | 2 min | | |
| 3 | Take final full backup of all user databases | `[X min]` | | |
| 4 | Drain active sessions | 5 min | | |
| **Side-by-side:** | | | | |
| 5a | Restore all user databases to target server | `[X min]` | | |
| 6a | Run login script on target | 10 min | | |
| 7a | Fix orphaned users — `sp_change_users_login` | 10 min | | |
| 8a | Restore SQL Agent jobs, operators, alerts | 15 min | | |
| 9a | Configure instance settings on target | 15 min | | |
| 10a | Flip DNS alias or update connection strings | 5 min | | |
| **In-place:** | | | | |
| 5b | Run SQL Server upgrade setup | `[X min]` | | |
| 6b | Confirm SQL Server service started | 5 min | | |
| **Both:** | | | | |
| 11 | Run post-migration validation suite | 20 min | | |
| 12 | Confirm application connectivity | 10 min | | |
| 13 | Capture post-migration baseline | 10 min | | |
| 14 | Go/No-Go decision — application owner sign-off | 10 min | | |
| 15 | Close maintenance window — notify stakeholders | 5 min | | |

**Total estimated duration:** `[X hours]`

---

## 6. Post-Change Validation

All items must pass before closing the change. Failures trigger rollback within the rollback deadline.

| # | Check | Pass Criteria |
|---|-------|---------------|
| 1 | SQL Server version on target | `SELECT @@VERSION` = expected target version |
| 2 | All databases ONLINE | `SELECT name, state_desc FROM sys.databases WHERE state <> 0` = 0 rows |
| 3 | AG synchronized (if applicable) | `Get-AvailabilityGroupReplicaState.sql` — all SYNCHRONIZED |
| 4 | Application connectivity | Application team confirms: ___________________________ |
| 5 | SQL Agent jobs present | `Get-SqlAgentJobOverview.sql` — all expected jobs present |
| 6 | Backup schedule will fire | `Get-BackupCoverage.sql` — next backup scheduled |
| 7 | No unexpected errors in error log | `Get-RecentErrorLogEntries.sql` — clean |

---

## 7. Rollback Plan

**Rollback decision owner:** `[Name]`
**Rollback deadline:** `[YYYY-MM-DD HH:MM]`
**Estimated rollback time:** `[X minutes]`

**Triggers that require immediate rollback:**
- Any user database fails to come ONLINE within 15 minutes
- Application cannot connect within 20 minutes of cutover
- AG cannot resynchronise within 30 minutes
- Data loss detected
- Rollback deadline reached with validation incomplete

**Rollback steps (side-by-side migration):**

| Step | Action |
|------|--------|
| 1 | Flip DNS alias or connection strings back to source server |
| 2 | Restart SQL Server Agent on source server |
| 3 | Confirm application connects to source: ___________________________ |
| 4 | Notify stakeholders — rollback complete |
| 5 | Raise post-incident review |

**Rollback steps (in-place upgrade — requires backup restore):**

| Step | Action |
|------|--------|
| 1 | SQL Server does not support downgrade — restore from backup to a new/parallel instance |
| 2 | Restore all databases from pre-migration backups to parallel SQL instance |
| 3 | Flip DNS alias or connection strings to restored instance |
| 4 | Notify stakeholders — rollback complete |

> **Note:** In-place upgrade rollback is significantly more complex and time-consuming.
> Side-by-side migration is strongly preferred for this reason.

Full rollback procedures: `sql-operations/rollback/migration-rollback-playbook.md`

---

## 8. Communication Plan

| Event | Notify | Method | Timing |
|-------|--------|--------|--------|
| Migration starting | Application team, management | Email / Slack | T-60 minutes |
| Migration underway | Application team | Slack | At start |
| Cutover complete — validation in progress | Application team | Slack | Post-restore |
| Validation passed — migration complete | All stakeholders | Email | At sign-off |
| Rollback initiated | Application team, management, change manager | Phone / Slack | Immediately |
| Rollback complete | All stakeholders | Email | At rollback complete |

**Contact list:**

| Role | Name | Phone | Email |
|------|------|-------|-------|
| DBA lead | | | |
| Application owner | | | |
| Management escalation | | | |
| Change manager | | | |
| On-call cover | | | |

---

## 9. Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Technical lead (DBA) | | | |
| Application owner | | | |
| Change manager | | | |
| CAB approval | | | |

---

*Attachments:*
- [ ] `Invoke-PreMigrationAssessment.ps1` output (CSV folder)
- [ ] Non-prod test evidence (screenshots / results)
- [ ] Pre-migration baseline (`Export-MigrationBaseline.ps1 -Label pre` output)
- [ ] Login script review (output of `Generate-LoginScript.ps1`)
