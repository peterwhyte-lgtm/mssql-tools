<#
.SYNOPSIS
Check today's collector CSVs against thresholds and output CRITICAL/WARNING findings.

.DESCRIPTION
Loads available collector CSV files for the specified date and server, applies threshold
checks across wait-stats (delta), blocking, tempdb, database-growth, and vlf-count.

Designed for SQL Agent CmdExec steps: exits 0 when nothing to alert, exits 1 if any
CRITICAL finding is detected (triggers step failure for notification routing).

Thresholds (production defaults):
  wait-stats:       PAGEIOLATCH_* > 40% CRITICAL / > 20% WARNING
  wait-stats:       RESOURCE_SEMAPHORE > 20% CRITICAL / > 10% WARNING
  wait-stats:       LCK_M_* > 30% CRITICAL / > 15% WARNING
  blocking:         any event = WARNING; wait_time > 60s CRITICAL / > 10s WARNING
  tempdb:           version_store_mb > 10000 CRITICAL / > 2000 WARNING
  tempdb:           free_mb (data file) < 100 CRITICAL / < 500 WARNING
  database-growth:  AT_LIMIT CRITICAL / NEAR_LIMIT WARNING
  vlf-count:        > 10000 VLFs CRITICAL / > 1000 WARNING

.PARAMETER ServerInstance
Target server. Defaults to $env:DBASCRIPTS_SERVER, then '.'.

.PARAMETER Date
Date to check (YYYYMMDD). Defaults to today.

.PARAMETER OutputFormat
Table (default) or Csv.

.PARAMETER OutputPath
Optional. Write findings to this CSV path (in addition to table output).

.EXAMPLE
.\collectors\Invoke-CollectorAlert.ps1
.\collectors\Invoke-CollectorAlert.ps1 -ServerInstance PROD01\SQL2019 -OutputFormat Csv

# SQL Agent job step (CmdExec) — exits 1 on CRITICAL to trigger failure notification:
# pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-scripts\collectors\Invoke-CollectorAlert.ps1"
#>
[CmdletBinding()]
param(
    [string]$ServerInstance,
    [string]$Date,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not $ServerInstance) {
    $ServerInstance = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '.' }
}
if (-not $Date) { $Date = Get-Date -Format 'yyyyMMdd' }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$safeName = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
if ($safeName -eq '.') { $safeName = $env:COMPUTERNAME }

function Get-CsvPath([string]$Collector) {
    Join-Path $repoRoot "output-files\collectors\$Collector\$safeName-$Date.csv"
}
function ToLong  ([object]$v) { try { [long][double]$v } catch { 0L } }
function ToDouble([object]$v) { try { [double]$v } catch { 0.0 } }

$findings = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Finding([string]$Severity, [string]$Collector, [string]$Check, [string]$Detail) {
    $findings.Add([PSCustomObject]@{
        Severity  = $Severity
        Collector = $Collector
        Check     = $Check
        Detail    = $Detail
        Server    = $ServerInstance
        CheckedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    })
}

# ---------------------------------------------------------------------------
# Wait-stats — cumulative delta
# ---------------------------------------------------------------------------
$wsPath = Get-CsvPath 'wait-stats'
if (Test-Path $wsPath) {
    try {
        $wsRows  = @(Import-Csv -LiteralPath $wsPath -Encoding UTF8)
        $times   = @($wsRows | Where-Object { $_.collection_time } |
                     Select-Object -ExpandProperty collection_time | Sort-Object -Unique)
        if ($times.Count -ge 2) {
            $t1 = $times[-2]; $t2 = $times[-1]
            $s1 = @($wsRows | Where-Object { $_.collection_time -eq $t1 })
            $s2 = @($wsRows | Where-Object { $_.collection_time -eq $t2 })

            if ($s1[0].sqlserver_start_time -ne $s2[0].sqlserver_start_time) {
                Add-Finding 'WARNING' 'wait-stats' 'restart detected' "sqlserver_start_time changed between $t1 and $t2 — delta skipped"
            } else {
                $h1 = @{}; foreach ($r in $s1) { $h1[$r.wait_type] = $r }
                $deltas = $s2 | ForEach-Object {
                    $p = $h1[$_.wait_type]; if (-not $p) { return }
                    $dw = [Math]::Max(0L, (ToLong $_.wait_time_ms) - (ToLong $p.wait_time_ms))
                    [PSCustomObject]@{ wait_type = $_.wait_type; delta_wait_ms = $dw }
                }
                $total = ($deltas | Measure-Object delta_wait_ms -Sum).Sum
                if ($total -gt 0) {
                    foreach ($pattern in @(
                        @{ Filter='PAGEIOLATCH_*'; Crit=40; Warn=20; Label='PAGEIOLATCH_* wait %' }
                        @{ Filter='RESOURCE_SEMAPHORE'; Crit=20; Warn=10; Label='RESOURCE_SEMAPHORE wait %' }
                        @{ Filter='LCK_M_*'; Crit=30; Warn=15; Label='LCK_M_* wait %' }
                    )) {
                        $ms  = ($deltas | Where-Object { $_.wait_type -like $pattern.Filter } |
                                Measure-Object delta_wait_ms -Sum).Sum
                        $pct = [Math]::Round($ms * 100.0 / $total, 1)
                        if ($pct -gt $pattern.Crit) {
                            Add-Finding 'CRITICAL' 'wait-stats' $pattern.Label "$($pattern.Filter) = $pct% (threshold >$($pattern.Crit)%) — interval $t1 → $t2"
                        } elseif ($pct -gt $pattern.Warn) {
                            Add-Finding 'WARNING'  'wait-stats' $pattern.Label "$($pattern.Filter) = $pct% (threshold >$($pattern.Warn)%) — interval $t1 → $t2"
                        }
                    }
                }
            }
        }
    } catch { Add-Finding 'WARNING' 'wait-stats' 'load error' $_.Exception.Message }
}

# ---------------------------------------------------------------------------
# Blocking — point-in-time (any row = noteworthy)
# ---------------------------------------------------------------------------
$blkPath = Get-CsvPath 'blocking'
if (Test-Path $blkPath) {
    try {
        $blkRows = @(Import-Csv -LiteralPath $blkPath -Encoding UTF8)
        if ($blkRows.Count -gt 0) {
            Add-Finding 'WARNING' 'blocking' 'blocking events recorded' "$($blkRows.Count) row(s) in $([IO.Path]::GetFileName($blkPath))"
            $blkRows | ForEach-Object {
                $ms = ToLong $_.wait_time_ms
                if ($ms -gt 60000) {
                    Add-Finding 'CRITICAL' 'blocking' 'blocking duration' "SPID $($_.blocked_spid) blocked $([Math]::Round($ms/1000,1))s by $($_.blocking_spid) — $($_.wait_type) — $($_.database_name) — $($_.collection_time)"
                } elseif ($ms -gt 10000) {
                    Add-Finding 'WARNING'  'blocking' 'blocking duration' "SPID $($_.blocked_spid) blocked $([Math]::Round($ms/1000,1))s by $($_.blocking_spid) — $($_.wait_type) — $($_.database_name) — $($_.collection_time)"
                }
            }
        }
    } catch { Add-Finding 'WARNING' 'blocking' 'load error' $_.Exception.Message }
}

# ---------------------------------------------------------------------------
# TempDB — point-in-time (latest snapshot)
# ---------------------------------------------------------------------------
$tdbPath = Get-CsvPath 'tempdb'
if (Test-Path $tdbPath) {
    try {
        $tdbRows = @(Import-Csv -LiteralPath $tdbPath -Encoding UTF8)
        if ($tdbRows.Count -gt 0) {
            $latest = $tdbRows | Where-Object { $_.collection_time } |
                Select-Object -ExpandProperty collection_time | Sort-Object -Unique -Descending | Select-Object -First 1
            @($tdbRows | Where-Object { $_.collection_time -eq $latest -and $_.row_type -eq 'file' -and $_.file_type -eq 'ROWS' }) | ForEach-Object {
                $vs = ToDouble $_.version_store_mb; $fr = ToDouble $_.free_mb
                if ($vs -gt 10000) { Add-Finding 'CRITICAL' 'tempdb' 'version_store_mb' "$($_.file_name): version_store_mb = $vs (>10000) — $latest" }
                elseif ($vs -gt 2000) { Add-Finding 'WARNING' 'tempdb' 'version_store_mb' "$($_.file_name): version_store_mb = $vs (>2000) — $latest" }
                if ($fr -lt 100)  { Add-Finding 'CRITICAL' 'tempdb' 'free_mb' "$($_.file_name): free_mb = $fr (<100 MB) — $latest" }
                elseif ($fr -lt 500) { Add-Finding 'WARNING' 'tempdb' 'free_mb' "$($_.file_name): free_mb = $fr (<500 MB) — $latest" }
            }
        }
    } catch { Add-Finding 'WARNING' 'tempdb' 'load error' $_.Exception.Message }
}

# ---------------------------------------------------------------------------
# Database-growth — point-in-time
# ---------------------------------------------------------------------------
$dbgPath = Get-CsvPath 'database-growth'
if (Test-Path $dbgPath) {
    try {
        $dbgRows = @(Import-Csv -LiteralPath $dbgPath -Encoding UTF8)
        if ($dbgRows.Count -gt 0) {
            $latest = $dbgRows | Where-Object { $_.collection_time } |
                Select-Object -ExpandProperty collection_time | Sort-Object -Unique -Descending | Select-Object -First 1
            @($dbgRows | Where-Object { $_.collection_time -eq $latest }) | ForEach-Object {
                if ($_.growth_status -eq 'AT_LIMIT') {
                    Add-Finding 'CRITICAL' 'database-growth' 'AT_LIMIT' "[$($_.database_name)] '$($_.logical_name)' at limit ($($_.file_size_mb) MB / $($_.growth_limit_mb) MB) — $latest"
                } elseif ($_.growth_status -eq 'NEAR_LIMIT') {
                    Add-Finding 'WARNING' 'database-growth' 'NEAR_LIMIT' "[$($_.database_name)] '$($_.logical_name)' $($_.space_to_limit_mb) MB to limit — $latest"
                }
            }
        }
    } catch { Add-Finding 'WARNING' 'database-growth' 'load error' $_.Exception.Message }
}

# ---------------------------------------------------------------------------
# VLF count — point-in-time
# ---------------------------------------------------------------------------
$vlfPath = Get-CsvPath 'vlf-count'
if (Test-Path $vlfPath) {
    try {
        $vlfRows = @(Import-Csv -LiteralPath $vlfPath -Encoding UTF8)
        if ($vlfRows.Count -gt 0) {
            $latest = $vlfRows | Where-Object { $_.collection_time } |
                Select-Object -ExpandProperty collection_time | Sort-Object -Unique -Descending | Select-Object -First 1
            @($vlfRows | Where-Object { $_.collection_time -eq $latest }) | ForEach-Object {
                $n = ToLong $_.vlf_count
                if ($n -gt 10000) { Add-Finding 'CRITICAL' 'vlf-count' 'vlf_count' "[$($_.database_name)] $n VLFs (>10000) — reuse_wait: $($_.log_reuse_wait_desc) — $latest" }
                elseif ($n -gt 1000) { Add-Finding 'WARNING' 'vlf-count' 'vlf_count' "[$($_.database_name)] $n VLFs (>1000) — reuse_wait: $($_.log_reuse_wait_desc) — $latest" }
            }
        }
    } catch { Add-Finding 'WARNING' 'vlf-count' 'load error' $_.Exception.Message }
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if ($findings.Count -eq 0) { exit 0 }

$crits = @($findings | Where-Object { $_.Severity -eq 'CRITICAL' })
$warns = @($findings | Where-Object { $_.Severity -eq 'WARNING'  })

$crits | ForEach-Object {
    Write-Host "  [CRITICAL] $($_.Collector) — $($_.Check)" -ForegroundColor Red
    Write-Host "             $($_.Detail)" -ForegroundColor DarkRed
}
$warns | ForEach-Object {
    Write-Host "  [WARNING]  $($_.Collector) — $($_.Check)" -ForegroundColor Yellow
    Write-Host "             $($_.Detail)" -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host "  $ServerInstance | $Date | CRITICAL: $($crits.Count) | WARNING: $($warns.Count)" -ForegroundColor DarkGray

if ($OutputFormat -eq 'Csv' -or $OutputPath) {
    $target = if ($OutputPath) { $OutputPath } else {
        Join-Path $repoRoot "output-files\collectors\alerts-$safeName-$Date.csv"
    }
    $findings | Sort-Object Severity, Collector | Export-Csv -LiteralPath $target -NoTypeInformation -Encoding UTF8
    Write-Host "  Findings written to: $target" -ForegroundColor DarkGray
}

if ($crits.Count -gt 0) { exit 1 } else { exit 0 }
