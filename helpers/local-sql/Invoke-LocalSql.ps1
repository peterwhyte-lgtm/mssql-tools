<#
.SYNOPSIS
Run an inline SQL query against a SQL Server instance.

.DESCRIPTION
Writes the query to a temp file and delegates to Invoke-RepoSql.ps1, keeping one
canonical execution path for the whole repo. Output and CSV behaviour are identical
to running a .sql file through Invoke-RepoSql.ps1 directly.

.PARAMETER Query
SQL query string to execute.

.PARAMETER ServerInstance
SQL Server instance. Defaults to '.' or $env:DBASCRIPTS_SERVER if set.

.PARAMETER Database
Initial database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER QueryTimeout
Command timeout in seconds. Default: 120.

.PARAMETER OutputFormat
'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional path to save CSV output.

.EXAMPLE
.\helpers\local-sql\Invoke-LocalSql.ps1 -Query "SELECT name FROM sys.databases ORDER BY name"
.\helpers\local-sql\Invoke-LocalSql.ps1 -Query "SELECT @@VERSION" -ServerInstance PROD01
.\helpers\local-sql\Invoke-LocalSql.ps1 -Query "SELECT * FROM sys.dm_exec_requests" -OutputFormat Csv
#>
param(
    [Parameter(Mandatory)]
    [string]$Query,

    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [int]$QueryTimeout      = 120,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$runner  = Join-Path $PSScriptRoot 'Invoke-RepoSql.ps1'
$tmpPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "inline-sql-$(Get-Date -Format 'yyyyMMddHHmmss').sql")

try {
    [IO.File]::WriteAllText($tmpPath, $Query, [Text.Encoding]::UTF8)
    & $runner -ScriptPath $tmpPath `
              -ServerInstance $ServerInstance `
              -Database       $Database `
              -Username       $Username `
              -Password       $Password `
              -QueryTimeout   $QueryTimeout `
              -OutputFormat   $OutputFormat `
              -OutputPath     $OutputPath
} finally {
    if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
}
