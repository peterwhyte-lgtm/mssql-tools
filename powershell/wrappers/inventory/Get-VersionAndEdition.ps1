<#
.SYNOPSIS
Shows SQL Server version, edition, patch level, and instance details.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Display core instance version, edition, cluster status, and patch level.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell/inventory/Get-VersionAndEdition.ps1
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
$sqlScript = Join-Path $repoRoot 'sql\inventory\Get-VersionAndEdition.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running version and edition info...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
