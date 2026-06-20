<#
.SYNOPSIS
Shows SQL Server error log entries from the last 24 hours, with routine noise filtered out.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Quick triage of unexpected errors without wading through backup/CHECKDB noise.

.DESCRIPTION
Wrapper for the Get-RecentErrorLogEntries SQL query. Reads the active error log via
xp_readerrorlog and returns up to 500 rows from the last 24 hours after filtering
common informational messages (backups, CHECKDB, I/O freeze/resume).

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\monitoring\Get-RecentErrorLogEntries.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\monitoring\Get-RecentErrorLogEntries.ps1 -ServerInstance MYSERVER -OutputFormat Csv -OutputPath .\output-files\recent-errors.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\monitoring\error-log\Get-RecentErrorLogEntries.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running recent error log review...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
