<#
.SYNOPSIS
Test SQL Server connectivity and print server details.

.DESCRIPTION
Verifies the target instance is reachable using the same Invoke-Sqlcmd / sqlcmd.exe
execution path as the rest of the repo. No ADO.NET dependency.

.PARAMETER ServerInstance
SQL Server instance. Defaults to '.' or $env:DBASCRIPTS_SERVER if set.

.PARAMETER Database
Initial database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.EXAMPLE
.\helpers\local-sql\Test-SqlConnectivity.ps1
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance PROD01\SQL2019
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance PROD01 -Username sa -Password 'P@ss'
#>
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$authLabel = if ($Username) { "SQL ($Username)" } else { 'Windows (integrated)' }

Write-Host ''
Write-Host "[connectivity] Server   : $ServerInstance" -ForegroundColor Cyan
Write-Host "[connectivity] Database : $Database" -ForegroundColor Cyan
Write-Host "[connectivity] Auth     : $authLabel" -ForegroundColor Cyan

$query = @"
SELECT
    @@SERVERNAME                            AS server_name,
    SERVERPROPERTY('Edition')               AS edition,
    SERVERPROPERTY('ProductVersion')        AS product_version,
    SERVERPROPERTY('ProductLevel')          AS product_level,
    DB_NAME()                               AS current_database,
    GETDATE()                               AS server_time;
"@

$row = $null

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $params = @{
        ServerInstance         = $ServerInstance
        Database               = $Database
        Query                  = $query
        QueryTimeout           = 15
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) { $params['Username'] = $Username; $params['Password'] = $Password }
    try   { $row = Invoke-Sqlcmd @params }
    catch { Write-Host "[connectivity] FAILED: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) {
        Write-Host "[connectivity] ERROR: Neither Invoke-Sqlcmd nor sqlcmd.exe is available." -ForegroundColor Red
        exit 1
    }
    $tmpSql = [IO.Path]::Combine([IO.Path]::GetTempPath(), "test-conn-$(Get-Date -Format 'yyyyMMddHHmmss').sql")
    try {
        [IO.File]::WriteAllText($tmpSql, $query, [Text.Encoding]::UTF8)
        $sqlArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $tmpSql, '-y', '0', '-b', '-C')
        if ($Username -and $Password) { $sqlArgs += @('-U', $Username, '-P', $Password) } else { $sqlArgs += '-E' }
        $lines = & $sqlcmdExe.Source @sqlArgs
        if ($LASTEXITCODE -ne 0) { Write-Host "[connectivity] FAILED: sqlcmd.exe exit $LASTEXITCODE" -ForegroundColor Red; exit 1 }
        if ($lines) {
            $row = [PSCustomObject]@{
                server_name      = $lines[0]; edition          = $lines[1]
                product_version  = $lines[2]; product_level    = $lines[3]
                current_database = $lines[4]; server_time      = $lines[5]
            }
        }
    } finally {
        if (Test-Path $tmpSql) { Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue }
    }
}

if ($row) {
    Write-Host ''
    Write-Host "[connectivity] Server name : $($row.server_name)"    -ForegroundColor Green
    Write-Host "[connectivity] Edition     : $($row.edition)"         -ForegroundColor Green
    Write-Host "[connectivity] Version     : $($row.product_version) · $($row.product_level)" -ForegroundColor Green
    Write-Host "[connectivity] Database    : $($row.current_database)" -ForegroundColor Green
    Write-Host "[connectivity] Server time : $($row.server_time)"     -ForegroundColor Green
    Write-Host ''
    Write-Host "[connectivity] Status      : OK" -ForegroundColor Green
    Write-Host ''
} else {
    Write-Host "[connectivity] No data returned — check parameters." -ForegroundColor Yellow
    exit 1
}
