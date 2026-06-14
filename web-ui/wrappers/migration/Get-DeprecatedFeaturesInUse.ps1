<#
.SYNOPSIS
Reports deprecated SQL Server features with active usage since last restart.
Use before a version upgrade to identify features that will generate errors or break
on the target version.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Pre-upgrade deprecated feature audit. Features with usage_count > 0
               are actively being used and must be remediated before upgrading.
               Complements Get-VersionUpgradeReadiness which provides the broader
               compatibility and sizing picture.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\database-admin\migration\powershell\Get-DeprecatedFeaturesInUse.ps1

.EXAMPLE
.\database-admin\migration\powershell\Get-DeprecatedFeaturesInUse.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'database-admin\migration\sql\Get-DeprecatedFeaturesInUse.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Checking deprecated feature usage (since last restart)...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
