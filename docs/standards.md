# Script standards

Authoritative reference for SQL and PowerShell script standards in this repo. `CONTRIBUTING.md` links here. `CLAUDE.md` has a condensed version — this file has the reasoning.

---

## SQL scripts

### Header

Every SQL script must open with this block comment, immediately followed by the safety annotations:

```sql
/*
Script Name : Get-ExampleScript
Category    : performance-troubleshooting
Purpose     : One-line description of what this returns.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
```

**Field values:**

| Field | Allowed values |
|-------|---------------|
| `Safe` | `Read-only` / `Writes data` / `Creates objects` |
| `Impact` | `Low` / `Medium` / `High` |
| `Requires` | Comma-separated permissions (`VIEW SERVER STATE`, `VIEW ANY DATABASE`, `sysadmin`, etc.) |
| `HealthCheck` | `Yes` — optional. Add only if this script runs as part of `Invoke-HealthCheckCollection.ps1`. Drives the Health Check Suite section in the web UI. |

The `-- SAFE:` and `-- IMPACT:` annotations on lines after the block comment are parsed by `Review-HealthCheckOutput.ps1` and the web UI. They must exactly match the pattern `-- SAFE:ReadOnly` / `-- SAFE:WritesData` / `-- SAFE:CreatesObjects` and `-- IMPACT:Low` / `-- IMPACT:Medium` / `-- IMPACT:High`.

### Rules

- **Single result set** — multi-result-set scripts cannot be exported as a single CSV via `Invoke-RepoSql.ps1`. If a script genuinely needs multiple result sets, it belongs in `sql/migration/` with its own orchestrator in `powershell/migration/`, not in `sql/`.
- **No `USE database; GO`** — pass `-Database` at execution time. `Invoke-Sqlcmd` does not support `GO` batch separators.
- **No `WITH (NOLOCK)`** without a comment explaining the risk. If you must use it, add `-- NOLOCK: <reason>` on the same line.
- **Modern DMVs only** — `sys.objects` not `sys.sysobjects`, `sys.server_principals` not `sys.syslogins`, `sys.dm_exec_sessions` not `sys.sysprocesses`.
- **`OUTER APPLY` not `CROSS APPLY`** when the applied function may return no rows (e.g. `sys.dm_exec_sql_text`).
- **No trailing blank lines** — 0–1 blank lines at end of file.
- **Deterministic output** — order by something meaningful. Unordered results make CSVs hard to diff.

### Where scripts go

| Category | Folder |
|----------|--------|
| Health, memory, jobs, TempDB, DBCC, config | `sql/monitoring/` |
| Waits, blocking, queries, indexes, I/O | `sql/performance/` |
| AG health and latency | `sql/ha-dr/` |
| Backup coverage, history, DR | `sql/backups/` |
| Roles, logins, permissions, surface area | `sql/security/` |
| Maintenance job generation and status | `sql/maintenance/` |
| Migration assessment and DDL generation | `sql/migration/` |

Every SQL script in `sql/` must have a matching wrapper in `powershell/wrappers/<same-category>/` — this is what makes it runnable from the web UI and `run.ps1`.

---

## PowerShell wrappers

Wrappers live in `powershell/wrappers/<category>/`. They are thin — SQL logic stays in the `.sql` file.

```powershell
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')   # powershell/wrappers/<cat>/ is 3 levels deep
$sqlScript = Join-Path $repoRoot 'sql\<category>\Get-Something.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
```

**Key points:**
- `$PSScriptRoot '..\..\..'` — wrappers sit at `powershell/wrappers/<category>/`, three levels from root.
- Migration script wrappers use `sql\migration\` instead of `sql\<category>\`.
- Always validate with `Test-Path` before invoking — gives a clear error instead of a cryptic PS exception.

Required `.NOTES` fields:

```powershell
.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : One-line description.
```

| Field | Values |
|-------|--------|
| `ScriptType` | `runner` / `automation` / `hybrid` |
| `TargetScope` | `single server` / `multi-server` |
| `RiskLevel` | `SAFE` / `MEDIUM` / `HIGH IMPACT` |

---

## PowerShell orchestrators

Scripts in `powershell/` have real logic — they are not thin wrappers. Same `.NOTES` fields apply. Resolve repo root with `$PSScriptRoot '..\..\..'` (also three levels deep).

---

## Standards audit

Run `.\tools\triage\Get-StandardsAudit.ps1` to check all SQL scripts for compliance. Covers: header presence, required fields, `SET NOCOUNT ON`, safety annotations, `WITH (NOLOCK)`, deprecated catalog views, `USE` statements, `GO` separators.
