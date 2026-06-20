<#
.SYNOPSIS
Server-level certificates and keys with expiry dates, usage (TDE/endpoint/EKM), and lifecycle risk flags.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Run the certificates and keys SQL query from the repo and export results.
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
$sqlScript = Join-Path $repoRoot 'sql\security\encryption\Get-CertificatesAndKeys.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'
if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }
Write-Host 'Checking certificates and encryption key lifecycle...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
