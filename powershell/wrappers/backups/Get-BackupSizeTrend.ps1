<#
.SYNOPSIS
Running backup size trend analysis.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'msdb',
    [ValidateSet('Table','Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\backups\Get-BackupSizeTrend.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running backup size trend analysis...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
