<#
.SYNOPSIS
Reads a health-check output folder and surfaces flagged findings with severity ratings.

.NOTES
ScriptType   : PowerShell-only
TargetScope  : output-files (offline review)
RiskLevel    : SAFE
Purpose      : Turn raw CSV collection output into an actionable findings list.

.DESCRIPTION
Reads the CSV files produced by Invoke-HealthCheckCollection.ps1 and applies threshold rules
to surface issues. Each finding is rated CRITICAL, WARNING, or INFO.

Rules applied:
  CRITICAL  - database not ONLINE
  CRITICAL  - database with no full backup ever
  WARNING   - full backup older than 25 hours
  WARNING   - log backup older than 4 hours for FULL recovery databases
  WARNING   - transaction log > 80% used
  WARNING   - auto_shrink enabled on any database
  WARNING   - SQL Agent job failures in the last 7 days
  WARNING   - percent-based autogrowth configured on any file
  INFO      - sessions with active blocking
  INFO      - sessions with open transactions
  INFO      - error log entries present (requires manual review)

.PARAMETER FolderPath
Path to the healthcheck output folder. If omitted, the most recent folder under
output-files\healthcheck is used.

.PARAMETER OutputFormat
'Table' (default) prints to console. 'Csv' writes findings to a CSV in the same folder.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1 -FolderPath ".\output-files\healthcheck\.-20260529-185000"

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1 -OutputFormat Csv
#>

param(
    [string]$FolderPath,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

if (-not $FolderPath) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
    if (-not (Test-Path -LiteralPath $hcRoot)) {
        throw "No FolderPath specified and no output-files\healthcheck directory found. Run Invoke-HealthCheckCollection.ps1 first."
    }
    $latest = Get-ChildItem -LiteralPath $hcRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) {
        throw "No healthcheck folders found under $hcRoot. Run Invoke-HealthCheckCollection.ps1 first."
    }
    $FolderPath = $latest.FullName
    Write-Host "No FolderPath specified — using most recent: $FolderPath" -ForegroundColor Yellow
}

if (-not (Test-Path -LiteralPath $FolderPath)) {
    throw "Folder not found: $FolderPath"
}

$findings = [System.Collections.Generic.List[PSObject]]::new()

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Category,
        [string]$Subject,
        [string]$Detail
    )
    $findings.Add([PSCustomObject]@{
        Severity = $Severity
        Category = $Category
        Subject  = $Subject
        Detail   = $Detail
    })
}

function Read-Csv-Safe {
    param([string]$Name)
    $path = Join-Path $FolderPath "$Name.csv"
    if (Test-Path -LiteralPath $path) {
        return @(Import-Csv -LiteralPath $path -ErrorAction SilentlyContinue)
    }
    return @()
}

# ── database-health ──────────────────────────────────────────────────────────
$dbHealth = Read-Csv-Safe 'database-health'
foreach ($row in $dbHealth) {
    if ($row.state_desc -and $row.state_desc -ne 'ONLINE') {
        Add-Finding 'CRITICAL' 'Database State' $row.database_name (
            "Database is $($row.state_desc)")
    }
    if ($row.is_auto_shrink_on -in @('True', '1', 'YES')) {
        Add-Finding 'WARNING' 'Auto-Shrink' $row.database_name (
            'AUTO_SHRINK is enabled — causes fragmentation and random I/O spikes')
    }
    if ($row.is_auto_close_on -in @('True', '1', 'YES')) {
        Add-Finding 'WARNING' 'Auto-Close' $row.database_name (
            'AUTO_CLOSE is enabled — causes overhead on every new connection')
    }
}

# ── backup-times ─────────────────────────────────────────────────────────────
$backups = Read-Csv-Safe 'backup-times'
foreach ($row in $backups) {
    $dbName = $row.database_name

    if (-not $row.last_full_backup -or $row.last_full_backup -eq '') {
        Add-Finding 'CRITICAL' 'Backup' $dbName 'No full backup on record'
    }
    elseif ([double]::TryParse($row.full_backup_age_hours, [ref]$null)) {
        $ageH = [double]$row.full_backup_age_hours
        if ($ageH -gt 25) {
            Add-Finding 'WARNING' 'Backup' $dbName (
                "Full backup is $([Math]::Round($ageH, 1)) hours old (threshold: 25h)")
        }
    }

    $recovery = $row.recovery_model_desc
    if ($recovery -eq 'FULL' -or $recovery -eq 'BULK_LOGGED') {
        if (-not $row.last_log_backup -or $row.last_log_backup -eq '') {
            Add-Finding 'WARNING' 'Backup' $dbName (
                "$recovery recovery model but no log backup on record — log will grow unbounded")
        }
        elseif ([double]::TryParse($row.log_backup_age_hours, [ref]$null)) {
            $logAgeH = [double]$row.log_backup_age_hours
            if ($logAgeH -gt 4) {
                Add-Finding 'WARNING' 'Backup' $dbName (
                    "Log backup is $([Math]::Round($logAgeH, 1)) hours old (threshold: 4h, $recovery recovery)")
            }
        }
    }
}

# ── tlog-usage ───────────────────────────────────────────────────────────────
$tlogs = Read-Csv-Safe 'tlog-usage'
foreach ($row in $tlogs) {
    if ([double]::TryParse($row.log_used_percent, [ref]$null)) {
        $pct = [double]$row.log_used_percent
        if ($pct -gt 80) {
            Add-Finding 'WARNING' 'Transaction Log' $row.database_name (
                "Log is $pct% used ($($row.log_used_mb) MB of $($row.log_size_mb) MB) — risk of log-full")
        }
    }
}

# ── database-files (autogrowth) ───────────────────────────────────────────────
$dbFiles = Read-Csv-Safe 'database-files'
foreach ($row in $dbFiles) {
    if ($row.growth_is_percent -in @('True', '1', 'YES', 'true')) {
        Add-Finding 'WARNING' 'Autogrowth' "$($row.database_name) / $($row.logical_name)" (
            "Percent-based autogrowth ($($row.auto_growth)) on $($row.file_type) file — can cause large unpredictable growths on large databases")
    }
}

# ── job-failures ─────────────────────────────────────────────────────────────
$jobs = Read-Csv-Safe 'job-failures'
$failedJobs = $jobs | Select-Object -ExpandProperty job_name -Unique
foreach ($jName in $failedJobs) {
    $count = @($jobs | Where-Object job_name -eq $jName).Count
    Add-Finding 'WARNING' 'SQL Agent' $jName (
        "$count failure(s) in the last 7 days")
}

# ── active-sessions (blocking) ────────────────────────────────────────────────
$sessions = Read-Csv-Safe 'active-sessions'
$blocked  = @($sessions | Where-Object {
    $_.blocking_session_id -and $_.blocking_session_id -ne '' -and $_.blocking_session_id -ne '0'
})
if ($blocked.Count -gt 0) {
    $blockedList = ($blocked | Select-Object -ExpandProperty session_id) -join ', '
    Add-Finding 'INFO' 'Blocking' 'Active sessions' (
        "$($blocked.Count) session(s) currently blocked: session_id(s) $blockedList")
}

$openTx = @($sessions | Where-Object {
    $_.open_transaction_count -and [int]$_.open_transaction_count -gt 0
})
if ($openTx.Count -gt 0) {
    Add-Finding 'INFO' 'Open Transactions' 'Active sessions' (
        "$($openTx.Count) session(s) with open transactions")
}

# ── recent-errors ─────────────────────────────────────────────────────────────
$errors = Read-Csv-Safe 'recent-errors'
if ($errors.Count -gt 0) {
    Add-Finding 'INFO' 'Error Log' 'SQL Server error log' (
        "$($errors.Count) non-routine entry/entries in last 24h — review recent-errors.csv")
}

# ── Output ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  DBA Health Check Review' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Folder : $FolderPath"
Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host '--------------------------------------------'

if ($findings.Count -eq 0) {
    Write-Host ''
    Write-Host '  No findings. All checked thresholds look healthy.' -ForegroundColor Green
    Write-Host ''
}
else {
    $order = @{ CRITICAL = 0; WARNING = 1; INFO = 2 }
    $sorted = $findings | Sort-Object { $order[$_.Severity] }, Category, Subject

    Write-Host ''
    foreach ($f in $sorted) {
        $color = switch ($f.Severity) {
            'CRITICAL' { 'Red' }
            'WARNING'  { 'Yellow' }
            default    { 'Cyan' }
        }
        Write-Host ("  [{0,-8}] {1,-22} {2}" -f $f.Severity, $f.Category, $f.Subject) -ForegroundColor $color
        Write-Host ("             {0}" -f $f.Detail) -ForegroundColor DarkGray
        Write-Host ''
    }

    $critCount = @($findings | Where-Object Severity -eq 'CRITICAL').Count
    $warnCount = @($findings | Where-Object Severity -eq 'WARNING').Count
    $infoCount = @($findings | Where-Object Severity -eq 'INFO').Count
    Write-Host '--------------------------------------------'
    Write-Host ("  CRITICAL: {0}  |  WARNING: {1}  |  INFO: {2}" -f $critCount, $warnCount, $infoCount) -ForegroundColor Cyan
    Write-Host ''

    if ($OutputFormat -eq 'Csv') {
        $csvOut = Join-Path $FolderPath 'findings.csv'
        $sorted | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8
        Write-Host "Findings written to: $csvOut" -ForegroundColor Green
        Write-Host ''
    }
}
