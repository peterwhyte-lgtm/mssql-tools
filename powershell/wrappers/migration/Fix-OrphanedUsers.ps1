<#
.SYNOPSIS
Generates ALTER USER statements to re-map orphaned database users to their
matching server-level logins across all user databases.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Read-only scan of all user databases for orphaned users. Returns ALTER USER
               statements ready to run on the TARGET after databases are restored and
               logins are re-created. Nothing is executed by this script.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\migration\Fix-OrphanedUsers.ps1

.EXAMPLE
.\powershell\wrappers\migration\Fix-OrphanedUsers.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\migration\Fix-OrphanedUsers.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Scanning for orphaned users and generating ALTER USER statements...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
