# DBA Scripts Roadmap

## Current state (updated 2026-06-03)

Fully functional production DBA toolkit. Since the initial build (2026-05-29), significant additions:

- **Multi-server scripts** — 10 standalone scripts (`tools/multi-server-scripts/`) covering disk, firewall, event logs, service status, service restart, TCP port testing, backup status, blocking, database sizes, and wait stats. Self-contained, copy-and-run anywhere.
- **Multi-server generator** — `helpers/multi-server-query/New-MultiServerScript.ps1` wraps any `.sql` or `.ps1` in a foreach/parallel loop. Fixed `$using:` bugs, added result collection with Server column, added credential template, `-ThrottleLimit` parameter.
- **Collector documentation** — all 8 collectors now have per-collector READMEs covering output columns, write conditions, collection frequency, SQL Agent T-SQL, and permissions.
- **Pester tests** — `tests/New-MultiServerScript.Tests.ps1` (18 tests, no SQL Server dependency).
- **Environment setup** — `Initialize-Environment.ps1` + `SETUP.md` for new machine onboarding.
- **Script headers** — all multi-server scripts have Params/Output/Example inline docs.

---

## Roadmap

### P3 — Active backlog (carry-over + new)

| Item | Type | Effort | Notes |
|------|------|--------|-------|
| `Invoke-MultiServerHealthCheck.ps1` | New PS | Medium | Server list → per-server collection → aggregated CRITICAL/WARNING report |
| `Get-DatabasePermissions.sql` + wrapper | New SQL | Small | Object-level explicit grants per database |
| `Get-ProxyAndCredentials.sql` + wrapper | New SQL | Small | SQL Agent proxies and credentials — privilege escalation surface |
| Collector delta analysis scripts | New PS | Medium | `Compare-CollectorSnapshots.ps1` — load two CSV files, produce diff table |
| `Invoke-CollectorAlert.ps1` | New PS | Medium | Check today's collector CSVs against thresholds, output CRITICAL/WARNING |
| Web UI caching | Bug/Perf | Small | `Get-AllScripts` + `Get-ScriptPurpose` + `Get-ScriptSafety` run on every page load — 2N disk reads per request |

### P4 — CI and quality gates (0% complete)

| Item | Notes |
|------|-------|
| GitHub Actions: Pester | `Invoke-Pester tests/` on push — currently 0 CI |
| GitHub Actions: PS syntax check | `$null = [System.Management.Automation.Language.Parser]::ParseFile()` per .ps1 |
| GitHub Actions: markdownlint | `.markdownlint.jsonc` already present, not wired to CI |
| SQLFluff T-SQL linting | Flag `NOLOCK`, deprecated catalog views, non-standard patterns |
| Broken link checker | Catch stale doc cross-references |

### P5 — New collectors

| Collector | Source | Value | Delta needed? |
|-----------|--------|-------|---------------|
| `query-store` | `sys.query_store_*` | Track plan regressions and query performance trends over time | No — point-in-time |
| `index-fragmentation` | `sys.dm_db_index_physical_stats` | Weekly snapshot — see which indexes degrade fastest | No — point-in-time |
| `vlf-count` | `sys.dm_db_log_info` | Track VLF accumulation before it becomes a maintenance emergency | No — point-in-time |
| `errorlog` | `sys.dm_os_ring_buffers` / `xp_readerrorlog` | Group SQL errorlog entries by severity + source over time | No — new events only |

Each would follow the existing collector pattern: one `.sql` + one `Collect-*.ps1` + one `README.md` with SQL Agent T-SQL.

### P6 — New SQL scripts

| Script | Category | Purpose |
|--------|----------|---------|
| `Get-TempDbConfiguration.sql` | monitoring | File count, sizing parity, relevant trace flags (T1118, T1117) |
| `Get-PlanCacheHealth.sql` | performance | Single-use plan ratio, memory pressure from ad-hoc queries |
| `Get-ReadableSecondaryUsage.sql` | high-availability | What queries are running on AG read replicas |
| `Get-BackupEncryptionStatus.sql` | backups | Backup encryption certificates and which databases are covered |
| `Get-LinkedServerSecurity.sql` | security | Linked server login mappings and security context |
| `Get-DatabasePermissions.sql` | security | Object-level explicit grants per database (P3 carry-over) |
| `Get-ProxyAndCredentials.sql` | security | SQL Agent proxies and credentials (P3 carry-over) |
| `Get-LockEscalationStats.sql` | performance | Lock escalation events and frequency from `sys.dm_os_wait_stats` |

### P7 — Larger ideas (no timeline)

| Idea | Description |
|------|-------------|
| Multi-server collector | Run any collector against a list of servers — `Invoke-MultiCollector.ps1 -Collector wait-stats -Servers "SVR01,SVR02"` |
| Baseline comparison | `Compare-MigrationBaseline.ps1` — load pre and post CSV sets, diff every metric, flag regressions |
| Trend forecasting | Given database growth collector data, calculate MB/day growth rate and project when disk runs out |
| Assessment scheduling | Run `Invoke-AssessmentReport.ps1` on a schedule via SQL Agent or Task Scheduler, email the output |
| Blog post automation | Tag a SQL script with `-- Blog: https://...` and have `Ensure-SqlHeaders.ps1` validate the link is live |

---

## Completion log

| Date | Item |
|------|------|
| 2026-06-03 | `Initialize-Environment.ps1` + `SETUP.md` — new machine onboarding script and full setup guide |
| 2026-06-03 | `tests/New-MultiServerScript.Tests.ps1` — 18 Pester tests for the generator, no SQL Server dependency |
| 2026-06-03 | 7 collector READMEs — blocking, deadlocks, tempdb, perfmon, ag-health, storage-io, database-growth |
| 2026-06-03 | Params/Output/Example added to all 10 multi-server script headers |
| 2026-06-03 | Multi-server scripts code review — fixed 6 bugs: $using: in parallel paths, GetRecentEventLogs catch, GetDatabaseSizes error loss, WebUI category label, README -Credential table, generator here-string guard |
| 2026-06-03 | `New-MultiServerScript.ps1` improvements — fixed $using: bugs, added -ThrottleLimit, result collection with Server column, credential template for PS remoting, updated helpers README |
| 2026-06-03 | `tools/multi-server-scripts/` — renamed from multi-server-queries, 10 scripts with compact headers, bug fixes (invalid Get-Service -Credential, WinRM documentation, parallel catch handling) |
| 2026-05-29 | Added `.gitignore`, healthcheck `-Quiet` switch, fixed `Invoke-RepoSql.ps1` category detection, archived `categories/`, rewrote `docs/standards.md`, deleted `docs/catalog.md` |
| 2026-05-29 | `run.ps1 -List` discovery mode, collection timestamp in review header, expanded `docs/runbook.md`, resolved `hybrid/` folder |
| 2026-05-29 | Full canonical `sql/` + `powershell/` layout, all scripts single-result-set, standard headers, no NOLOCK, no deprecated catalog views |
| 2026-05-29 | 8 collectors with SQL + PS orchestrator pairs: wait-stats, blocking, deadlocks, tempdb, perfmon, ag-health, storage-io, database-growth |
| 2026-05-29 | `Invoke-HealthCheckCollection.ps1` (22 scripts) + `Review-HealthCheckOutput.ps1` (17 rule categories) |
