<#
.SYNOPSIS
Returns sessions involved in blocking chains with wait type, timing, and current statement.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Show blocking sessions with wait info and current SQL text.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Get-BlockingSessions.ps1

.EXAMPLE
.\run.ps1 Get-BlockingSessions -ServerInstance MYSERVER\INST01
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\performance\Get-BlockingSessions.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

Write-Host 'Running blocking-sessions review...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
