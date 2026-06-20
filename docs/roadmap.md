# DBA Scripts Roadmap

## Current state (updated 2026-06-14)

Fully functional production DBA toolkit. The repo has a category-first layout: `sql/` for SQL scripts, `powershell/` for wrappers, orchestrators, and automation (categories mirror `sql/`), and `docs/ops/` for operational runbooks and change templates.

**What is complete:**
- SQL diagnostic layer — 80+ scripts across monitoring, performance, high-availability, backups, security, maintenance, migration
- Wrapper layer — 81 thin PS wrappers, one per SQL script, colocated with the web UI
- PowerShell orchestration — healthcheck collection (32 scripts), review, assessment report, multi-server health check
- Migration toolkit — full pre/post assessment, DDL generators (logins, jobs, linked servers, user mappings), baseline export
- Collectors — 12 scheduled data collectors with paired SQL + PS, READMEs, SQL Agent T-SQL
- Collector analysis — `Compare-CollectorSnapshots.ps1`, `Invoke-CollectorAlert.ps1`
- Multi-server scripts — 12 self-contained scripts for fleet-wide operations
- Browser UI — script browser, CSV viewer, triage page, health check runner
- Environment setup — `Initialize-Environment.ps1` + `SETUP.md`
- Pester tests — path resolution smoke tests, multi-server generator tests

---

## Active backlog

### Phase 3 — Script blog coverage (ongoing, Peter-driven)

Per-script public documentation lives on sqldba.blog, not in the repo. For each script that merits a post:

1. Draft in `blog/<slug>/index.md` using `blog/_template/index.md`
2. Publish to sqldba.blog
3. Optionally add the live URL to the script's row in `docs/script-catalog.md`

The repo's internal documentation layer is the script header only (Purpose, Requires, SAFE/IMPACT annotations). Internal docs otherwise stay light and general — no per-script READMEs or sidecars.

### Phase 4 — CI and quality gates (complete 2026-06-17)

| Item | Status | Notes |
|------|--------|-------|
| GitHub Actions: Pester | ✅ | `Invoke-Pester tests/` on push — SqlPathResolution, WrapperParity, New-MultiServerScript |
| GitHub Actions: PSScriptAnalyzer | ✅ | Covers all `.ps1` under sql/, powershell/, web-ui/, tools/ |
| GitHub Actions: markdownlint | ✅ | `.markdownlint.jsonc` wired via ci.yaml (excludes blog/ and CLAUDE.md) |
| GitHub Actions: SQL standards audit | ✅ | `Get-StandardsAudit.ps1 -FailsOnly` — fails CI on any FAIL status |
| GitHub Actions: secrets scan | ✅ | gitleaks on full history |
| SQLFluff | — | Not added — Get-StandardsAudit covers NOLOCK, deprecated views, USE, GO |

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
| 2026-06-20 | CONTRIBUTING.md rewrite — Peter Whyte as lead and author established; mission statement; SQL header Author field fixed to Peter Whyte (https://sqldba.blog); Pester test instructions added |
| 2026-06-20 | README.md — author identity added to What This Is; health check count corrected 27→32; AssessedBy placeholder fixed; Contributing blurb updated |
| 2026-06-20 | docs/standards.md — wrapper depth updated to cover both 3-level and 4-level cases with subfoldered path example |
| 2026-06-20 | CLAUDE.md — outdated standards.md caveat corrected; both files now described as in sync |
| 2026-06-20 | CI fix — Get-ActiveRequests.ps1 and Get-BlockingChains.ps1 path references corrected to active-sessions/ and blocking-locking/ subdirs; 4 Pester failures resolved; 635/635 passing |
| 2026-06-17 | Phase 4 CI — SQL standards audit job added to ci.yaml; Get-StandardsAudit.ps1 updated to exit 1 on failures and validate annotation position; WrapperParity.Tests.ps1 added; blog/ role and Phase 3 definition clarified in CLAUDE.md, roadmap, and standards.md; sub-READMEs (tools/, powershell/, tools/local-sql/) updated to remove stale script references |
| 2026-06-17 | CLAUDE.md update — SQL header standard revised: Safe/Impact removed from block comment, inline annotations moved above SET NOCOUNT ON; 146 SQL scripts, 3 doc files, CONTRIBUTING.md, and Get-StandardsAudit.ps1 updated to match; blog posts corruption fixed (40 files); repo-structure.md, standards.md, quick-start.md aligned to CLAUDE.md layout; Get-Databases.ps1 wrapper added |
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
| 2026-05-29 | `Invoke-HealthCheckCollection.ps1` (32 scripts) + `Review-HealthCheckOutput.ps1` |
