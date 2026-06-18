<#
.SYNOPSIS
Shows failed, retrying, and unsent database mail items with error detail.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'msdb',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..') 
$sqlScript = Join-Path $repoRoot 'sql\monitoring\Get-DatabaseMailQueue.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Checking database mail queue...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
