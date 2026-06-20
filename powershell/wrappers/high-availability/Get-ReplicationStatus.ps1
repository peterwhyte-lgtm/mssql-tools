<#
.SYNOPSIS
Lists all publications and subscriptions from the distribution database.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'distribution',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\high-availability\replication\Get-ReplicationStatus.sql'
$runner = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner)) { throw "Runner not found: $runner" }

Write-Host 'Listing replication publications and subscriptions...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
