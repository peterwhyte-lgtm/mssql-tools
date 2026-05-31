# Contributing

Bug reports, fixes, and improvements to existing scripts are welcome. This is a production DBA toolkit, so the bar for changes is correctness and safety — not feature completeness.

---

## Reporting issues

Open a GitHub issue with:

- SQL Server version and edition
- The script name and the exact error or unexpected output
- What you expected vs what you got

For security issues, see [SECURITY.md](SECURITY.md).

---

## Pull requests

Small, focused PRs are preferred over large ones. Before opening a PR:

- Check that the script runs cleanly against SQL Server 2016+ (the minimum supported version)
- Confirm it is read-only if it claims to be — no unintended writes
- Run it against at least one real instance before submitting

### SQL script standards

Every SQL script must have this header immediately before `SET NOCOUNT ON`:

```sql
/*
Script Name : Get-ExampleScript
Category    : performance-troubleshooting
Purpose     : One-line description of what this returns.
Author      : Your Name
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
```

`Safe` values: `Read-only` / `Writes data` / `Creates objects`
`Impact` values: `Low` / `Medium` / `High`

Additional rules:

- Single result set — multi-result-set scripts cannot be exported as CSV via the repo runner
- No `USE database; GO` — pass `-Database` at execution time instead
- No `WITH (NOLOCK)` without a comment explaining why
- Modern DMVs only — `sys.objects` not `sys.sysobjects`, `sys.server_principals` not `sys.syslogins`
- `OUTER APPLY` not `CROSS APPLY` when the applied function may return no rows

### PowerShell script standards

Wrappers follow a thin-wrapper pattern — SQL logic stays in external `.sql` files, not in PowerShell strings.

```powershell
# Standard wrapper shape
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $repoRoot 'sql\<category>\Get-Something.sql'
$runner    = Join-Path $repoRoot 'helpers\local-sql\Invoke-RepoSql.ps1'
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
```

Required `.NOTES` fields: `ScriptType` (runner / automation / hybrid), `TargetScope` (single server / multi-server), `RiskLevel` (SAFE / MEDIUM / HIGH IMPACT).

### Where new scripts go

| Type | Location |
|------|----------|
| New SQL diagnostic or monitoring script | `sql/<category>/Get-Something.sql` |
| New PowerShell wrapper | `powershell/<subcategory>/Get-Something.ps1` |
| New change order template | `sql-operations/change-orders/` |
| New operational checklist | `sql-operations/checklists/` |

If the right category doesn't exist, open an issue first rather than creating a new top-level folder.

---

## What's out of scope

- Scripts that require elevated permissions beyond `VIEW SERVER STATE` / `VIEW ANY DATABASE` without a strong reason
- Scripts that modify data or schema (unless clearly labelled and placed in a separate category)
- Vendor-specific or non-SQL-Server scripts
- Test frameworks or CI tooling changes without prior discussion
