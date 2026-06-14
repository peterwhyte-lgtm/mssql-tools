<#
.SYNOPSIS
Runs post-migration validation checks and produces a summary result set for comparison between source and target.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Produce a comparable summary of key server state (database count, logins, jobs, config) to validate migration completeness.

.DESCRIPTION
A convenience wrapper for the repo's post-migration validation SQL query.
Run on BOTH the source and target server. Export both as CSV (using -OutputFormat Csv),
then diff the two files. The value column should match for each check_name row.

Checks include: user database count, databases not ONLINE, total/SQL/Windows login counts,
sysadmin count, linked server count, agent job count, instance version, edition,
max server memory, MAXDOP, and TempDB data file count.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'. Use 'Csv' on both source and target then diff.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
# Run on source
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\migration\Get-PostMigrationValidation.ps1 -ServerInstance SOURCE -OutputFormat Csv -OutputPath .\output-files\migration\source-validation.csv

.EXAMPLE
# Run on target
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\migration\Get-PostMigrationValidation.ps1 -ServerInstance TARGET -OutputFormat Csv -OutputPath .\output-files\migration\target-validation.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $repoRoot 'sql\migration\Get-PostMigrationValidation.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host "Running post-migration validation against [$ServerInstance]..." -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
