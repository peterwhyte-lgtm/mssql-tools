<#
.SYNOPSIS
Scheduled SQL Server error log collector — appends new entries to daily CSV.

.DESCRIPTION
Reads the SQL Server error log and appends only entries newer than the most
recently captured log_date, preventing duplicates on back-to-back runs.

Output: output-files\collectors\errorlog\<server>-<YYYYMMDD>.csv

.EXAMPLE
.\collectors\errorlog\Collect-Errorlog.ps1
.\collectors\errorlog\Collect-Errorlog.ps1 -ServerInstance PROD01\SQL2019
#>
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $PSScriptRoot 'errorlog.sql'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\collectors\errorlog' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$safeName = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
$today    = Get-Date -Format 'yyyyMMdd'
$csvPath  = Join-Path $OutputRoot "$safeName-$today.csv"
$logPath  = Join-Path $OutputRoot "$safeName-collector.log"
$ts       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Write-CollectorLog { param([string]$Msg, [string]$Level = 'INFO')
    $line = "[$ts] [$Level] $Msg"
    Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    if ($Host.Name -ne 'Default Host') { Write-Host $line }
}

# Determine last captured log entry to avoid duplicates
$lastCaptured = [datetime]'2000-01-01'
if (Test-Path $csvPath) {
    try {
        $existing = Import-Csv $csvPath -ErrorAction SilentlyContinue |
            Where-Object { $_.log_date } |
            Select-Object -ExpandProperty log_date |
            ForEach-Object { [datetime]$_ } |
            Sort-Object -Descending | Select-Object -First 1
        if ($existing) { $lastCaptured = $existing }
    } catch { Write-CollectorLog "Could not read existing CSV: $($_.Exception.Message)" 'WARN' }
}

Write-CollectorLog "Starting errorlog collection — server: $ServerInstance, since: $lastCaptured"

$rows = $null
$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $p = @{ ServerInstance=$ServerInstance; Database=$Database; InputFile=$sqlScript
            QueryTimeout=30; TrustServerCertificate=$true; ErrorAction='Stop' }
    if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }
    try   { $rows = @(Invoke-Sqlcmd @p) }
    catch { Write-CollectorLog "Invoke-Sqlcmd failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { Write-CollectorLog 'No SQL tool available.' 'ERROR'; exit 1 }
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "el-$(Get-Date -Format 'yyyyMMddHHmmss').tmp.csv")
    $a = @('-S',$ServerInstance,'-d',$Database,'-i',$sqlScript,'-b','-r','1','-t','30','-C','-o',$tmp,'-W','-w','4000','-s',',')
    if ($Username -and $Password) { $a += @('-U',$Username,'-P',$Password) } else { $a += '-E' }
    try {
        & $sqlcmdExe.Source @a
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe exit $LASTEXITCODE" }
        if (Test-Path $tmp) {
            $raw  = @(Import-Csv -LiteralPath $tmp -ErrorAction Stop)
            $rows = @($raw | Where-Object { $r=$_; -not ($r.PSObject.Properties.Name | Where-Object { $r.$_ -match '^-+$' }) })
        }
    } catch { Write-CollectorLog "sqlcmd.exe failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }
}

if (-not $rows -or $rows.Count -eq 0) {
    Write-CollectorLog 'No log entries returned.'; exit 0
}

# Filter to new entries only
$newRows = @($rows | Where-Object {
    try { [datetime]$_.log_date -gt $lastCaptured } catch { $false }
})

if ($newRows.Count -eq 0) {
    Write-CollectorLog 'No new entries since last capture.'; exit 0
}

$newRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8

$errors   = @($newRows | Where-Object { $_.severity -eq 'Error' }).Count
$warnings = @($newRows | Where-Object { $_.severity -eq 'Warning' }).Count
$msg = "$($newRows.Count) new entry/entries appended (Errors: $errors, Warnings: $warnings)"
Write-CollectorLog $msg (if ($errors -gt 0) { 'WARN' } else { 'INFO' })