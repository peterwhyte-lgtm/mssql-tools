<#
.SYNOPSIS
Reports SQL Server version, Cumulative Update level, edition, and build number
for patch-level tracking. Use across the estate to identify servers that need patching.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Single-server patch level check. For fleet-wide patch inventory use
               MultiServer-GetPatchLevel.ps1 in powershell/multi-server/sql/.
               Compare product_version against sqlserverupdates.com for latest CU.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\monitoring\Get-PatchLevel.ps1

.EXAMPLE
.\powershell\wrappers\monitoring\Get-PatchLevel.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\inventory\Get-PatchLevel.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Checking SQL Server patch level...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
