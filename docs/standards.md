# Script standards

## SQL header format

Every SQL script in `sql/` uses this exact format:

```sql
/*
Script Name : Get-ExampleScript
Category    : <performance-troubleshooting | monitoring | backups | security | migration>
Purpose     : One-line operational description of what the script returns.
Author      : Peter Whyte (https://sqldba.blog)
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

## PowerShell header format

```powershell
<#
.SYNOPSIS
One-line description.

.NOTES
ScriptType   : hybrid | automation | runner
TargetScope  : single server | multi-server
RiskLevel    : SAFE | MEDIUM | HIGH IMPACT
Purpose      : Operational purpose.
#>
```

## Rules

- **Single result set**: All canonical `sql/` scripts must return one result set. `Invoke-RepoSql.ps1` captures only the first result set for CSV; multi-result-set scripts silently lose data.
- **No `WITH (NOLOCK)`**: Use snapshot isolation or document the trade-off explicitly if you add it.
- **No deprecated catalog views**: Use `sys.objects` not `sys.sysobjects`; `sys.server_principals` not `sys.syslogins`; `sys.columns` not `sys.syscolumns`.
- **No `USE database; GO`**: `Invoke-Sqlcmd` does not support `GO` batch separators. Pass `-Database` at execution time instead.
- **`OUTER APPLY` not `CROSS APPLY`** when the applied function may return no rows (e.g. `sys.dm_exec_sql_text(NULL)`).
- **AG scripts**: Guard with `IF SERVERPROPERTY('IsHadrEnabled') = 0 OR NOT EXISTS (SELECT 1 FROM sys.availability_groups)` and return a status row — don't throw on non-AG instances.
- **No trailing blank lines**: Keep files clean; 0–1 blank lines at end of file.
