<#
.SYNOPSIS
Scores the SQL Server instance across key configuration checks — returns PASS/WARN/FAIL per item.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\reporting\Get-InstanceConfigurationScore.ps1 -ServerInstance PROD01\SQL2019
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
$sqlScript = Join-Path $repoRoot 'sql\monitoring\Get-InstanceConfigurationScore.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running instance configuration score...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
