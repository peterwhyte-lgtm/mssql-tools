<#
.SYNOPSIS
Project when database files will hit their configured size limits based on historical growth data.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Project when database files will hit their configured size limits based on historical growth data.
Depends On   : sql\collectors\Generate-CollectorJob-DatabaseGrowth.sql must be installed and collecting.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Database where the growth collector stores data. Defaults to 'DBAMonitor'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\run.ps1 Get-DatabaseGrowthForecast

.EXAMPLE
.\powershell\wrappers\monitoring\disk-space\Get-DatabaseGrowthForecast.ps1 -ServerInstance PROD01\SQL2019 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'DBAMonitor',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\monitoring\disk-space\Get-DatabaseGrowthForecast.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running Get-DatabaseGrowthForecast...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
