# DBA Scripts Roadmap

## Current state (as of 2026-05-29)

The repo is a functional, comprehensive production DBA toolkit. Key capabilities:

- **SQL scripts**: ~45 canonical scripts across `sql/monitoring/`, `sql/performance/`, `sql/backups/`, `sql/security/`, `sql/migration/`
- **PS wrappers**: Every SQL script has a matching PS wrapper — no coverage gaps
- **Healthcheck workflow**: `Invoke-HealthCheckCollection.ps1` collects 19 scripts → `Review-HealthCheckOutput.ps1` flags 17 rule categories (CRITICAL / WARNING / INFO)
- **Security coverage**: server roles, database roles, orphaned users, login permissions, weak login settings, surface area config
- **Standards**: all canonical SQL scripts have standard headers, `SET NOCOUNT ON`, safety annotations, no NOLOCK, no deprecated catalog views

---

## Fresh-eyes review findings (production DBA first look)

These are the friction points a DBA would hit on first use, in order of impact.

### 1. No `.gitignore` — output CSVs will be committed accidentally

`output-files/` accumulates `.csv` and `.tmp.csv` files every time a script runs. There is no `.gitignore`. A DBA who does `git add .` will commit hundreds of CSV files. `output-files/test-backup-review/` also contains `.bak` fixture files that appear to be committed by accident.

**Fix:** Add `.gitignore` covering `output-files/**/*.csv`, `.tmp.csv`, `output-files/healthcheck/`, and standard PS/SQL patterns.

---

### 2. Healthcheck collection is extremely noisy

`Invoke-HealthCheckCollection.ps1` prints `[repo-sql]` headers for every script (5 lines each × 19 scripts = 95+ lines of noise) plus 25-row table previews. The summary and output folder path are buried at the bottom.

**Fix:** Add a `-Quiet` switch that suppresses per-script verbose output, showing only the `[OK]` / `[FAILED]` status lines and the final summary.

---

### 3. `categories/` is a silent source of confusion

`categories/` contains old copies of most scripts — many with older content (missing bug fixes, wrong formulas, old headers). `docs/catalog.md` still pointed to `categories/` paths throughout.

**Fix:** Add `categories/ARCHIVED.md` redirecting to `sql/` and `powershell/`. Delete `docs/catalog.md`.

---

### 4. `docs/standards.md` and `docs/catalog.md` were stale and misleading

`docs/standards.md` showed the OLD header format conflicting with what scripts actually use. `docs/catalog.md` was a legacy-paths catalog pointing to `categories/` everywhere.

**Fix:** Delete `docs/catalog.md`. Rewrite `docs/standards.md` to match the actual header format.

---

### 5. `Invoke-RepoSql.ps1` used `categories/` path logic for CSV output naming

Scripts run from `sql/monitoring/` were categorised as `general` in the output path.

**Fix:** Update the regex to also detect `sql/monitoring`, `sql/performance`, etc.

---

### 6. No discovery mode in `run.ps1`

Running `.\run.ps1` with no script name threw. No way to browse available scripts.

**Fix:** Add `-List` mode showing all scripts grouped by category.

---

### 7. `hybrid/` folder was empty but documented as a key layer

All three subfolders (`agent-job-monitoring/`, `backup-validation/`, `sql-inventory-reporting/`) were empty.

**Fix:** Delete the empty subfolders. Update `hybrid/README.md` to reflect current state.

---

### 8. `docs/runbook.md` was a skeleton

The daily runbook was 10 lines with no paths, commands, or thresholds.

**Fix:** Expand into a genuine daily/weekly/incident runbook with canonical commands, thresholds, and scenario coverage.

---

### 9. Review findings had no collection timestamp

No visible signal that findings may be from stale data.

**Fix:** Parse the timestamp from the folder name and show "Collected: YYYY-MM-DD HH:MM:SS" in the review header.

---

### 10. No multi-server support

Every script targets a single `$ServerInstance`.

**Status:** Deferred — see P3.

---

## Roadmap priorities

### P1 — Completed 2026-05-29

| Item | Status |
|------|--------|
| Add `.gitignore` | ✓ Complete |
| Healthcheck `-Quiet` switch | ✓ Complete |
| Fix `Invoke-RepoSql.ps1` category detection | ✓ Complete |
| Delete `docs/catalog.md` | ✓ Complete |
| Rewrite `docs/standards.md` | ✓ Complete |
| Archive `categories/` with ARCHIVED.md | ✓ Complete |

### P2 — Completed 2026-05-29

| Item | Status |
|------|--------|
| `run.ps1` list/discovery mode (`-List`) | ✓ Complete |
| Collection timestamp in review output header | ✓ Complete |
| Expand `docs/runbook.md` | ✓ Complete |
| Resolve `hybrid/` — delete empty subfolders, update README | ✓ Complete |

### P3 — Pending

| Item | Effort | Notes |
|------|--------|-------|
| `Get-DatabasePermissions.sql` + wrapper | Small | Object-level explicit grants per database |
| `Get-ProxyAndCredentials.sql` + wrapper | Small | Agent proxies and credentials (privilege escalation surface) |
| `Invoke-MultiServerHealthCheck.ps1` | Medium | Server list file → per-server collection → consolidated findings |

### P4 — CI and quality gates (currently 0/10)

| Item | Notes |
|------|-------|
| SQLFluff T-SQL linting | GitHub Actions, flag unsafe patterns |
| markdownlint | Enforce docs consistency |
| Broken link checker | Flag stale `categories/` references in docs |
| PS wrapper smoke test | Assert every wrapper resolves its SQL path at import time |

---

## Completion log

| Date | Item |
|------|------|
| 2026-05-29 | Added `.gitignore` — covers CSVs, .bak files, healthcheck output |
| 2026-05-29 | Healthcheck `-Quiet` switch — `Invoke-HealthCheckCollection.ps1` |
| 2026-05-29 | Fixed `Invoke-RepoSql.ps1` category detection — now resolves `sql/monitoring`, `sql/performance` etc. |
| 2026-05-29 | Deleted `docs/catalog.md` — was pointing to stale `categories/` paths |
| 2026-05-29 | Rewrote `docs/standards.md` — matches actual header format in use |
| 2026-05-29 | Archived `categories/` — added ARCHIVED.md, empty subfolders not searched by overview tools |
| 2026-05-29 | `run.ps1` list/discovery mode — `.\run.ps1 -List` shows all scripts grouped by category |
| 2026-05-29 | Collection timestamp in review header — `Review-HealthCheckOutput.ps1` now shows when data was collected |
| 2026-05-29 | Expanded `docs/runbook.md` — real daily/weekly/incident runbook with canonical commands and thresholds |
| 2026-05-29 | Resolved `hybrid/` — deleted empty subfolders, updated README to reflect current state |
| 2026-05-29 | Created CLAUDE.md — full architecture, usage patterns, healthcheck table, and standards reference |
| 2026-05-29 | Full canonical `sql/` + `powershell/` layout with zero PS wrapper coverage gaps |
| 2026-05-29 | All SQL scripts single-result-set, standard headers, no NOLOCK, no deprecated catalog views |
| 2026-05-29 | Bug fixes: TempDB growth formula, TransactionLog used vs free column naming, MemoryConfig multi-result-set, BlockingSessions OUTER APPLY, AG non-AG guard, SqlAgentJobFailureSummary unreadable int dates |
| 2026-05-29 | Key improvements: WaitStatistics benign wait filter + pct_total, LongRunningQueries DB_NAME + seconds, MissingIndexes impact score + suggested statement, BlockingSummary head-blocker context |
| 2026-05-29 | New diagnostic scripts: OsAndHardwareInfo, DatabaseFilesDetail, RecentErrorLogEntries, ActiveSessions, LastDbccCheckdb, SuspectPages, JobScheduleSummary, TopIoQueries, IndexUsageStats, SlowQueriesFromCache |
| 2026-05-29 | Security suite: ServerRoleMembers, DatabaseRoleMembers, OrphanedUsers, LoginPermissions, WeakLoginSettings + powershell/security/ wrappers |
| 2026-05-29 | `Invoke-HealthCheckCollection.ps1` (19 scripts) + `Review-HealthCheckOutput.ps1` (17 rule categories) |
| 2026-05-29 | `powershell/migration/` folder with wrappers for all 4 migration SQL scripts |
| 2026-05-29 | Canonical layout under `sql/`, `powershell/`, `helpers/`, `docs/` with top-level `run.ps1` launcher |
