# DBA Scripts Roadmap

## Current state (updated 2026-06-14)

Fully functional production DBA toolkit. The repo has a category-first layout: `sql/` for SQL scripts, `powershell/` for wrappers, orchestrators, and automation (categories mirror `sql/`), and `docs/ops/` for operational runbooks and change templates.

**What is complete:**
- SQL diagnostic layer — 80+ scripts across monitoring, performance, ha-dr, backups, security, maintenance, migration
- Wrapper layer — 81 thin PS wrappers, one per SQL script, colocated with the web UI
- PowerShell orchestration — healthcheck collection (27 scripts), review, assessment report, multi-server health check
- Migration toolkit — full pre/post assessment, DDL generators (logins, jobs, linked servers, user mappings), baseline export
- Collectors — 12 scheduled data collectors with paired SQL + PS, READMEs, SQL Agent T-SQL
- Collector analysis — `Compare-CollectorSnapshots.ps1`, `Invoke-CollectorAlert.ps1`
- Multi-server scripts — 12 self-contained scripts for fleet-wide operations
- Browser UI — script browser, CSV viewer, triage page, health check runner
- Environment setup — `Initialize-Environment.ps1` + `SETUP.md`
- Pester tests — path resolution smoke tests, multi-server generator tests

---

## Active backlog

### Phase 3 — Per-script documentation (not started)

For each SQL script in `sql/`: add an inline `README` or blog entry covering:
- Purpose in operational terms (not just what the columns are)
- Example output interpretation — what does a bad result look like?
- When **not** to use it
- Required permissions
- Known caveats (e.g. DMV resets on restart, AG guard behaviour)

### Phase 4 — CI and quality gates (not started)

| Item | Notes |
|------|-------|
| GitHub Actions: Pester | `Invoke-Pester tests/` on push |
| GitHub Actions: PS syntax check | `[System.Management.Automation.Language.Parser]::ParseFile()` per .ps1 |
| GitHub Actions: markdownlint | `.markdownlint.jsonc` is present, not wired to CI |
| SQLFluff T-SQL linting | Flag `NOLOCK`, deprecated catalog views, non-standard patterns |
| Broken link / path checker | Catch stale cross-references in docs and wrapper SQL paths |

---

## Larger ideas (no timeline)

| Idea | Description |
|------|-------------|
| Multi-server collector | Run any collector against a list of servers — `Invoke-MultiCollector.ps1 -Collector wait-stats -Servers "SVR01,SVR02"` |
| Baseline comparison | `Compare-MigrationBaseline.ps1` — load pre and post CSV sets, diff every metric, flag regressions |
| Trend forecasting | Given database growth collector data, project when disk runs out based on MB/day growth rate |
| Assessment scheduling | Run `Invoke-AssessmentReport.ps1` on a schedule via SQL Agent or Task Scheduler, email the output |

---

## Completion log

| Date | Item |
|------|------|
| 2026-06-15 | Moved thin wrappers to `powershell/wrappers/<cat>/` — clean separation from orchestrators; PSScriptRoot depth 3 levels; all tooling and docs updated |
| 2026-06-14 | Repo restructure — category-first layout: `sql/`, `powershell/`, `powershell/runners/`, `docs/ops/`; all path references updated across 132+ files |
| 2026-06-05 | `wrappers/` top-level folder — 81 thin PS wrappers separated from `powershell/`, mirrors `sql/` category structure |
| 2026-06-05 | Phase 2 PS standards — `.NOTES` block (ScriptType, TargetScope, RiskLevel, Purpose) added to all remaining non-compliant PS scripts |
| 2026-06-05 | 7 new PS wrappers — Get-Heaps, Get-UnusedIndexes, Get-CompatibilityLevelAudit, Get-MigrationLoginAudit, Get-PostMigrationValidation, Generate-LinkedServerScript, Generate-RestoreWithMoveScript |
| 2026-06-05 | `docs/repo-structure.md` and `docs/script-catalog.md` — accurate structure and full script list |
| 2026-06-04 | Generate-BackupJobs/IndexMaintenanceJobs/MaintenanceJobs — fixed OutputFormat=Csv path so web UI renders DDL as code block |
| 2026-06-04 | Web UI — collapsible SQL categories, Workflows section, IsWrapper detection, chart improvements, threshold markers |
| 2026-06-03 | P6 SQL scripts — Get-TempDbConfiguration, Get-PlanCacheHealth, Get-ReadableSecondaryUsage, Get-BackupEncryptionStatus, Get-LinkedServerSecurity, Get-DatabasePermissions, Get-ProxyAndCredentials, Get-LockEscalationStats |
| 2026-06-03 | `Invoke-MultiServerHealthCheck.ps1` — server list → per-server collection → aggregated CRITICAL/WARNING report |
| 2026-06-03 | `Compare-CollectorSnapshots.ps1`, `Invoke-CollectorAlert.ps1` — post-incident collector analysis and threshold alerting |
| 2026-06-03 | Collectors: query-store, index-fragmentation, vlf-count, errorlog — all 12 collectors now complete with READMEs |
| 2026-06-03 | `Initialize-Environment.ps1` + `SETUP.md` — new machine onboarding |
| 2026-06-03 | `tests/New-MultiServerScript.Tests.ps1`, `tests/SqlPathResolution.Tests.ps1` — Pester smoke tests |
| 2026-06-03 | Multi-server scripts — 12 self-contained scripts, parallel execution, credential template, result collection with Server column |
| 2026-05-29 | Full canonical layout, all scripts single-result-set, standard headers, no NOLOCK, no deprecated catalog views |
| 2026-05-29 | 8 initial collectors — wait-stats, blocking, deadlocks, tempdb, perfmon, ag-health, storage-io, database-growth |
| 2026-05-29 | `Invoke-HealthCheckCollection.ps1` (27 scripts) + `Review-HealthCheckOutput.ps1` |
