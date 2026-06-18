<#
.SYNOPSIS
Stops and drops a named Extended Events session.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : MEDIUM
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
$sqlScript = Join-Path $repoRoot 'sql\traces\Remove-XeSession.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Removing XE session...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
