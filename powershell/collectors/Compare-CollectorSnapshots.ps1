﻿<#
.SYNOPSIS
Computes interval deltas between two adjacent collector snapshots.

.DESCRIPTION
For cumulative collectors (wait-stats, storage-io, perfmon), loads two adjacent
snapshots from the daily CSV and computes the delta for each metric. Detects SQL
Server restarts between snapshots and warns if the delta would be invalid.

For point-in-time collectors (blocking, deadlocks, tempdb, ag-health, vlf-count,
database-growth, errorlog, query-store, index-fragmentation), shows the latest
snapshot directly — no delta calculation needed.

.PARAMETER Collector
Required. One of: wait-stats, storage-io, perfmon, blocking, deadlocks, tempdb,
ag-health, database-growth, vlf-count, errorlog, query-store, index-fragmentation

.PARAMETER ServerInstance
SQL Server name (used to build the CSV filename). Defaults to env var or '.'.

.PARAMETER Date
Date to analyse. Format: YYYYMMDD. Defaults to today.

.PARAMETER Top
Limit output to this many rows. Default: 25.

.PARAMETER Snapshot1
Optional — use this specific collection_time as the 'before' snapshot.

.PARAMETER Snapshot2
Optional — use this specific collection_time as the 'after' snapshot.

.EXAMPLE
.\collectors\Compare-CollectorSnapshots.ps1 -Collector wait-stats
.\collectors\Compare-CollectorSnapshots.ps1 -Collector storage-io -Date 20260601 -Top 10
.\collectors\Compare-CollectorSnapshots.ps1 -Collector blocking -ServerInstance PROD01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('wait-stats','storage-io','perfmon','blocking','deadlocks','tempdb',
                 'ag-health','database-growth','vlf-count','errorlog','query-store',
                 'index-fragmentation')]
    [string]$Collector,

    [string]$ServerInstance,
    [string]$Date,
    [int]$Top = 25,
    [string]$Snapshot1,
    [string]$Snapshot2
)

$ErrorActionPreference = 'Stop'

# Resolve server name for filename
if (-not $ServerInstance) { $ServerInstance = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '.' } }
$safeName = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
if ($safeName -eq '.') { $safeName = $env:COMPUTERNAME }

if (-not $Date) { $Date = Get-Date -Format 'yyyyMMdd' }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$csvPath  = Join-Path $repoRoot "output-files\collectors\$Collector\$safeName-$Date.csv"

if (-not (Test-Path $csvPath)) {
    Write-Host "No CSV found: $csvPath" -ForegroundColor Yellow
    Write-Host "Run the collector first: .\collectors\$Collector\Collect-*.ps1" -ForegroundColor DarkGray
    return
}

$data = @(Import-Csv $csvPath -ErrorAction Stop)
if ($data.Count -eq 0) { Write-Host "CSV is empty: $csvPath" -ForegroundColor Yellow; return }

Write-Host ''
Write-Host "  Collector : $Collector" -ForegroundColor Cyan
Write-Host "  Server    : $ServerInstance" -ForegroundColor Cyan
Write-Host "  Date      : $Date" -ForegroundColor Cyan
Write-Host "  File      : $csvPath" -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------------------
# Cumulative collectors — compute delta between two snapshots
# ---------------------------------------------------------------------------

$cumulativeCollectors = @('wait-stats', 'storage-io', 'perfmon')

if ($Collector -in $cumulativeCollectors) {
    $times = @($data | Select-Object -ExpandProperty collection_time -Unique | Sort-Object)
    if ($times.Count -lt 2) {
        Write-Host "  Only $($times.Count) snapshot(s) in file — need at least 2 for a delta." -ForegroundColor Yellow
        Write-Host "  Snapshots available: $($times -join ', ')" -ForegroundColor DarkGray
        return
    }

    # Pick snapshots
    $t1 = if ($Snapshot1) { $Snapshot1 } else { $times[-2] }
    $t2 = if ($Snapshot2) { $Snapshot2 } else { $times[-1] }

    Write-Host "  Snapshot 1 : $t1" -ForegroundColor DarkGray
    Write-Host "  Snapshot 2 : $t2" -ForegroundColor DarkGray
    Write-Host ''

    $snap1 = @($data | Where-Object { $_.collection_time -eq $t1 })
    $snap2 = @($data | Where-Object { $_.collection_time -eq $t2 })

    # Restart detection (cumulative collectors include sqlserver_start_time)
    if ($snap1[0].sqlserver_start_time -and $snap2[0].sqlserver_start_time) {
        if ($snap1[0].sqlserver_start_time -ne $snap2[0].sqlserver_start_time) {
            Write-Host "  WARNING: SQL Server restarted between snapshots!" -ForegroundColor Red
            Write-Host "  Snap1 start_time: $($snap1[0].sqlserver_start_time)" -ForegroundColor Yellow
            Write-Host "  Snap2 start_time: $($snap2[0].sqlserver_start_time)" -ForegroundColor Yellow
            Write-Host "  Delta values are not meaningful — counters reset on restart." -ForegroundColor Yellow
            Write-Host ''
        }
    }

    switch ($Collector) {
        'wait-stats' {
            $s1h = $snap1 | Group-Object wait_type -AsHashTable -AsString
            $deltas = $snap2 | ForEach-Object {
                $prev = $s1h[$_.wait_type]
                if (-not $prev) { return }
                $dw = [long]$_.wait_time_ms - [long]$prev.wait_time_ms
                $dt = [long]$_.waiting_tasks_count - [long]$prev.waiting_tasks_count
                if ($dw -le 0) { return }
                [PSCustomObject]@{
                    wait_type       = $_.wait_type
                    delta_wait_ms   = $dw
                    delta_tasks     = $dt
                    avg_wait_ms     = if ($dt -gt 0) { [Math]::Round($dw / $dt, 1) } else { 0 }
                    max_wait_ms     = [long]$_.max_wait_time_ms
                }
            }
            $totalMs = ($deltas | Measure-Object delta_wait_ms -Sum).Sum
            $deltas | Sort-Object delta_wait_ms -Descending | Select-Object -First $Top |
                ForEach-Object {
                    $_ | Add-Member -NotePropertyName pct_of_interval -NotePropertyValue (
                        if ($totalMs -gt 0) { [Math]::Round(100.0 * $_.delta_wait_ms / $totalMs, 1) } else { 0 }
                    ) -PassThru
                } | Format-Table wait_type, delta_wait_ms, delta_tasks, avg_wait_ms, pct_of_interval, max_wait_ms -AutoSize
        }

        'storage-io' {
            $s1h = $snap1 | Group-Object { "$($_.database_name)|$($_.file_id)" } -AsHashTable -AsString
            $snap2 | ForEach-Object {
                $key  = "$($_.database_name)|$($_.file_id)"
                $prev = $s1h[$key]
                if (-not $prev) { return }
                $dr = [long]$_.num_of_reads  - [long]$prev.num_of_reads
                $dw = [long]$_.num_of_writes - [long]$prev.num_of_writes
                $rs = [long]$_.io_stall_read_ms  - [long]$prev.io_stall_read_ms
                $ws = [long]$_.io_stall_write_ms - [long]$prev.io_stall_write_ms
                if ($dr + $dw -le 0) { return }
                [PSCustomObject]@{
                    database_name    = $_.database_name
                    file_type        = $_.file_type
                    interval_reads   = $dr
                    interval_writes  = $dw
                    avg_read_ms      = if ($dr -gt 0) { [Math]::Round($rs / $dr, 2) } else { 0 }
                    avg_write_ms     = if ($dw -gt 0) { [Math]::Round($ws / $dw, 2) } else { 0 }
                    read_stall_ms    = $rs
                    write_stall_ms   = $ws
                }
            } | Sort-Object { $_.read_stall_ms + $_.write_stall_ms } -Descending |
                Select-Object -First $Top |
                Format-Table database_name, file_type, interval_reads, avg_read_ms, interval_writes, avg_write_ms -AutoSize
        }

        'perfmon' {
            # Only cumulative counters (cntr_type 272696576) are meaningful to diff
            $s1h = $snap1 | Where-Object { $_.cntr_type -eq '272696576' } |
                Group-Object { "$($_.counter_name)|$($_.instance_name)" } -AsHashTable -AsString
            $snap2 | Where-Object { $_.cntr_type -eq '272696576' } | ForEach-Object {
                $key  = "$($_.counter_name)|$($_.instance_name)"
                $prev = $s1h[$key]
                if (-not $prev) { return }
                $delta = [long]$_.cntr_value - [long]$prev.cntr_value
                if ($delta -lt 0) { return }
                [PSCustomObject]@{
                    counter_name  = $_.counter_name
                    instance_name = $_.instance_name
                    delta_value   = $delta
                }
            } | Sort-Object delta_value -Descending | Select-Object -First $Top |
                Format-Table counter_name, instance_name, delta_value -AutoSize
        }
    }
} else {
    # ---------------------------------------------------------------------------
    # Point-in-time collectors — show latest snapshot
    # ---------------------------------------------------------------------------
    $latest = ($data | Select-Object -ExpandProperty collection_time -Unique | Sort-Object)[-1]
    Write-Host "  Latest snapshot: $latest ($($data.Count) total rows in file)" -ForegroundColor DarkGray
    Write-Host ''
    $data | Where-Object { $_.collection_time -eq $latest } |
        Select-Object -First $Top | Format-Table -AutoSize
}