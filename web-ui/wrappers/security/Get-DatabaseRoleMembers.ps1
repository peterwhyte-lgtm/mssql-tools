<#
.SYNOPSIS
Lists database role memberships across all online user databases.

.NOTES
ScriptType   : hybrid
TargetScope  : single server (iterates all user databases)
RiskLevel    : SAFE
Purpose      : Answer "who can do what in which database" in one pass.

.DESCRIPTION
Wrapper for the Get-DatabaseRoleMembers SQL query. Uses dynamic SQL to collect
db_owner, db_datareader, db_datawriter, and custom role memberships from every
online user database in a single result set.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\database-admin\powershell-scripts\security\Get-DatabaseRoleMembers.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\database-admin\powershell-scripts\security\Get-DatabaseRoleMembers.ps1 -OutputFormat Csv -OutputPath .\output-files\db-roles.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'database-admin\sql-scripts\security\Get-DatabaseRoleMembers.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running database role members review...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
