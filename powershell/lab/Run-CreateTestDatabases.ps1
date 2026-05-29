<#
.SYNOPSIS
Runs the New-TestDatabases SQL script with parameter substitution via sqlcmd.

.NOTES
ScriptType   : automation
TargetScope  : single server
RiskLevel    : HIGH IMPACT — creates databases
Purpose      : Simple SQL-driven test database creation. For SMO-based bulk creation
               with explicit file paths use New-MultipleDatabases.ps1 instead.

.PARAMETER Count            Number of databases to create. Defaults to 10.
.PARAMETER Prefix           Name prefix. Defaults to 'migdb'.
.PARAMETER StartIndex       Starting index. Defaults to 1.
.PARAMETER DataSizeMB       Initial data file size in MB. Defaults to 25.
.PARAMETER LogSizeMB        Initial log file size in MB. Defaults to 10.
.PARAMETER ServerInstance   Target SQL Server instance. Defaults to '.'.

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File .\powershell\lab\Run-CreateTestDatabases.ps1 -Count 5 -Prefix demo

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File .\powershell\lab\Run-CreateTestDatabases.ps1 -Count 20 -Prefix migdb -DataSizeMB 50
#>

param(
    [int]   $Count          = 10,
    [string]$Prefix         = 'migdb',
    [int]   $StartIndex     = 1,
    [int]   $DataSizeMB     = 25,
    [int]   $LogSizeMB      = 10,
    [string]$ServerInstance = '.'
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$scriptPath = Join-Path $repoRoot 'sql\lab\New-TestDatabases.sql'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "SQL script not found: $scriptPath"
}

$source = Get-Content -LiteralPath $scriptPath -Raw
$source = $source -replace 'DECLARE @Count\s+INT\s*=\s*\d+;',      "DECLARE @Count      INT     = $Count;"
$source = $source -replace "DECLARE @Prefix\s+SYSNAME\s*=\s*N'[^']*';", "DECLARE @Prefix     SYSNAME = N'$Prefix';"
$source = $source -replace 'DECLARE @StartIndex\s+INT\s*=\s*\d+;',  "DECLARE @StartIndex INT     = $StartIndex;"
$source = $source -replace 'DECLARE @DataSizeMB\s+INT\s*=\s*\d+;',  "DECLARE @DataSizeMB INT     = $DataSizeMB;"
$source = $source -replace 'DECLARE @LogSizeMB\s+INT\s*=\s*\d+;',   "DECLARE @LogSizeMB  INT     = $LogSizeMB;"

$tempFile = Join-Path $env:TEMP "new-test-databases-$([guid]::NewGuid().ToString('N')).sql"
Set-Content -Path $tempFile -Value $source -Encoding UTF8

Write-Host "Creating $Count databases with prefix '$Prefix' on $ServerInstance..." -ForegroundColor Cyan

try {
    $output = & sqlcmd -S $ServerInstance -C -b -r 1 -i $tempFile 2>&1
    $output | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed with exit code $LASTEXITCODE"
    }
    Write-Host "Done." -ForegroundColor Green
}
finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}
