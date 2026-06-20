<#
.SYNOPSIS
Scans the plan cache for implicit conversion warnings causing index scans and CPU waste.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Run the implicit conversions SQL query from the repo and export results.
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\performance\queries\Get-ImplicitConversions.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Scanning plan cache for implicit conversion warnings (may take 10-30s on busy servers)...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
