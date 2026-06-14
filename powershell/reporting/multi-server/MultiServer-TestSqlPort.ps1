﻿<#
Script Name : MultiServer-TestSqlPort
Category    : multi-server-scripts/powershell
Purpose     : Test TCP connectivity to SQL Server port 1433 (or custom port) on multiple servers. No WinRM needed.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : Nothing — uses System.Net.Sockets.TcpClient.
Params      : -Servers "SVR01,SVR02"   Required. Hostnames, IPs, or SERVER\INSTANCE (instance part stripped).
              -Port 1433               TCP port to test. Default: 1433.
              -Timeout 1000            Connection timeout in milliseconds. Default: 1000.
              -Parallel                Run all tests simultaneously.
Output      : Server, Port, Reachable, LatencyMs, Error
Example     : .\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02,SVR03" -Parallel
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [int]$Port = 1433,
    [int]$Timeout = 1000,
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'

# Parse server list — strip instance names (SERVER\INSTANCE → SERVER)
$serverList = $Servers -split ',' | ForEach-Object {
    $s = $_.Trim()
    if ($s -match '^([^\\]+)\\') { $Matches[1] } else { $s }
} | Where-Object { $_ -ne '' } | Select-Object -Unique

if ($serverList.Count -eq 0) {
    Write-Error "-Servers contained no valid hostnames."
    exit 1
}

function Test-TcpPort([string]$server, [int]$port, [int]$timeout) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $asyncResult = $client.BeginConnect($server, $port, $null, $null)
        $connected   = $asyncResult.AsyncWaitHandle.WaitOne($timeout, $false)
        if ($connected -and $client.Connected) {
            $client.EndConnect($asyncResult)
            return [PSCustomObject]@{ Server = $server; Port = $port; Reachable = $true; LatencyMs = ''; Error = '' }
        } else {
            return [PSCustomObject]@{ Server = $server; Port = $port; Reachable = $false; LatencyMs = ''; Error = 'Connection timed out' }
        }
    } catch {
        return [PSCustomObject]@{ Server = $server; Port = $port; Reachable = $false; LatencyMs = ''; Error = $_.Exception.Message }
    } finally {
        $client.Dispose()
    }
}

$results = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Testing $($serverList.Count) server(s) in parallel (port $Port, ${Timeout}ms timeout)..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv = $_
        $p   = $using:Port
        $t   = $using:Timeout
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $ar = $client.BeginConnect($srv, $p, $null, $null)
            $ok = $ar.AsyncWaitHandle.WaitOne($t, $false)
            if ($ok -and $client.Connected) {
                $client.EndConnect($ar)
                [PSCustomObject]@{ Server = $srv; Port = $p; Reachable = $true; Error = '' }
            } else {
                [PSCustomObject]@{ Server = $srv; Port = $p; Reachable = $false; Error = 'Timed out' }
            }
        } catch {
            [PSCustomObject]@{ Server = $srv; Port = $p; Reachable = $false; Error = $_.Exception.Message }
        } finally {
            $client.Dispose()
        }
    } -ThrottleLimit 20 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "  Testing $server`:$Port..." -NoNewline
        $sw  = [System.Diagnostics.Stopwatch]::StartNew()
        $r   = Test-TcpPort -server $server -port $Port -timeout $Timeout
        $sw.Stop()
        if ($r.Reachable) { $r.LatencyMs = $sw.ElapsedMilliseconds }
        $clr = if ($r.Reachable) { 'Green' } else { 'Red' }
        $msg = if ($r.Reachable) { " OPEN  ($($r.LatencyMs)ms)" } else { " CLOSED  $($r.Error)" }
        Write-Host $msg -ForegroundColor $clr
        $results.Add($r)
    }
}

$open   = @($results | Where-Object { $_.Reachable }).Count
$closed = @($results | Where-Object { -not $_.Reachable }).Count

Write-Host "`n── Summary ──────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Open: $open   Closed/unreachable: $closed   Port: $Port" -ForegroundColor $(if ($closed -gt 0) { 'Yellow' } else { 'Green' })
$results | Sort-Object Reachable, Server | Format-Table Server, Port, Reachable, LatencyMs, Error -AutoSize