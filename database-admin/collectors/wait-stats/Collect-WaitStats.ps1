<#
.SYNOPSIS
Scheduled wait stats collector — appends a snapshot to the daily CSV.

.DESCRIPTION
Captures a raw snapshot of sys.dm_os_wait_stats and appends it to a rolling daily
CSV at output-files\collectors\wait-stats\<server>-<YYYYMMDD>.csv.

Designed for SQL Agent / Task Scheduler execution. Silent when no console is attached.
Each run appends one batch of rows (one row per wait type). Adjacent snapshots can be
diffed to measure waits within a collection interval.

IMPORTANT: sys.dm_os_wait_stats is cumulative since SQL Server start. The sqlserver_start_time
column in the output detects restarts so invalid deltas can be discarded.

.PARAMETER ServerInstance
Target SQL Server instance. Defaults to '.' or $env:DBASCRIPTS_SERVER if set.

.PARAMETER Database
Connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputRoot
Root folder for output. Defaults to output-files\collectors\wait-stats\ under repo root.

.EXAMPLE
# Run manually
.\collectors\wait-stats\Collect-WaitStats.ps1

# Run against a remote server
.\collectors\wait-stats\Collect-WaitStats.ps1 -ServerInstance PROD01\SQL2019

# SQL Agent job step command (CmdExec):
# pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\mssql-tools\collectors\wait-stats\Collect-WaitStats.ps1"
#>
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

# ── Connection defaults from session env vars ─────────────────────────────────
if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

# ── Paths ─────────────────────────────────────────────────────────────────────
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $PSScriptRoot 'wait-stats.sql'

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'output-files\collectors\wait-stats'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
$today     = Get-Date -Format 'yyyyMMdd'
$csvPath   = Join-Path $OutputRoot "$safeName-$today.csv"
$logPath   = Join-Path $OutputRoot "$safeName-collector.log"

# ── Logging (SQL Agent job history has limited display; write to file too) ────
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
function Write-CollectorLog {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[$ts] [$Level] $Msg"
    Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    if ($Host.Name -ne 'Default Host') { Write-Host $line }
}

Write-CollectorLog "Starting wait-stats collection — server: $ServerInstance"

# ── Execute SQL ───────────────────────────────────────────────────────────────
$rows = $null

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $params = @{
        ServerInstance         = $ServerInstance
        Database               = $Database
        InputFile              = $sqlScript
        QueryTimeout           = 30
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) { $params['Username'] = $Username; $params['Password'] = $Password }
    try   { $rows = @(Invoke-Sqlcmd @params) }
    catch { Write-CollectorLog "Invoke-Sqlcmd failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) {
        Write-CollectorLog 'Neither Invoke-Sqlcmd nor sqlcmd.exe available.' 'ERROR'
        exit 1
    }
    $tmpCsv  = [IO.Path]::Combine([IO.Path]::GetTempPath(), "ws-$(Get-Date -Format 'yyyyMMddHHmmss').tmp.csv")
    $sqlArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $sqlScript,
                 '-b', '-r', '1', '-t', '30', '-C', '-o', $tmpCsv,
                 '-W', '-w', '4000', '-s', ',')
    if ($Username -and $Password) { $sqlArgs += @('-U', $Username, '-P', $Password) }
    else                          { $sqlArgs += '-E' }
    try {
        & $sqlcmdExe.Source @sqlArgs
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe exit $LASTEXITCODE" }
        if (Test-Path $tmpCsv) {
            $raw  = @(Import-Csv -LiteralPath $tmpCsv -ErrorAction Stop)
            $rows = @($raw | Where-Object {
                $r = $_; -not ($r.PSObject.Properties.Name | Where-Object { $r.$_ -match '^-+$' })
            })
        }
    } catch {
        Write-CollectorLog "sqlcmd.exe failed: $($_.Exception.Message)" 'ERROR'
        exit 1
    } finally {
        if (Test-Path $tmpCsv) { Remove-Item $tmpCsv -Force -ErrorAction SilentlyContinue }
    }
}

# ── Append to daily CSV ───────────────────────────────────────────────────────
if (-not $rows -or $rows.Count -eq 0) {
    Write-CollectorLog 'Query returned no rows — SQL Server may have just restarted.' 'WARN'
    exit 0
}

$fileExists = Test-Path $csvPath
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8

$verb = if ($fileExists) { 'appended' } else { 'created' }
Write-CollectorLog "OK — $($rows.Count) wait types $verb to $([IO.Path]::GetFileName($csvPath))"
