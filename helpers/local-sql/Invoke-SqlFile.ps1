<#
.SYNOPSIS
Backward-compatibility stub — delegates directly to Invoke-RepoSql.ps1.

.DESCRIPTION
Invoke-RepoSql.ps1 is the canonical SQL execution path for this repo.
This file exists only so existing callers do not break. Prefer calling
Invoke-RepoSql.ps1 directly for all new work.

.PARAMETER ScriptPath
Path to the .sql file to run.

.PARAMETER ServerInstance
SQL Server instance. Defaults to '.' or $env:DBASCRIPTS_SERVER if set.

.PARAMETER Database
Initial database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER QueryTimeout
Command timeout in seconds. Default: 600.

.PARAMETER OutputFormat
'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional path to save CSV output.

.EXAMPLE
.\helpers\local-sql\Invoke-SqlFile.ps1 -ScriptPath .\sql\performance\Get-WaitStatistics.sql
#>
param(
    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [int]$QueryTimeout      = 600,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

& (Join-Path $PSScriptRoot 'Invoke-RepoSql.ps1') `
    -ScriptPath     $ScriptPath `
    -ServerInstance $ServerInstance `
    -Database       $Database `
    -Username       $Username `
    -Password       $Password `
    -QueryTimeout   $QueryTimeout `
    -OutputFormat   $OutputFormat `
    -OutputPath     $OutputPath
