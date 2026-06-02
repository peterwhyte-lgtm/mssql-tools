<#
Script Name : MultiServer-TestSqlPort
Category    : multi-server-queries/powershell
Purpose     : Test TCP connectivity to SQL Server port 1433 (or a custom port) on
              multiple servers. No WinRM or credentials required — pure TCP test.
              Use this before running SQL scripts to confirm port access, or to audit
              which servers in an estate are reachable over SQL Server's default port.
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low (initiates TCP connections to test reachability only)
Requires    : Nothing — uses System.Net.Sockets.TcpClient, no modules or WinRM needed.

Parameters:
  -Servers     Required. Comma-separated hostnames, IPs, or SERVER\INSTANCE strings.
               Named instances are extracted to hostname only for port testing.
               Examples: "SVR01,SVR02,SVR03\INST01,192.168.1.10"
  -Port        TCP port to test. Default: 1433 (SQL Server default instance).
               Use 1434 for SQL Browser, or specify a custom port.
  -Timeout     Connection timeout in milliseconds. Default: 1000 (1 second).
  -Parallel    Run all tests simultaneously instead of sequentially. Default: sequential.

Usage examples:
  # Test SQL Server port on five servers
  .\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05"

  # Test a custom port with a longer timeout
  .\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02" -Port 1435 -Timeout 3000

  # Quick parallel sweep of many servers
  .\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05,SVR06" -Parallel
#>

[CmdletBinding()]
param (
    # Comma-separated server list — SERVER\INSTANCE is handled (instance part stripped for port test)
    [Parameter(Mandatory)]
    [string]$Servers,

    # TCP port to test — default 1433 (SQL Server default instance port)
    [int]$Port = 1433,

    # Connection timeout in milliseconds — default 1000ms (1 second)
    [int]$Timeout = 1000,

    # Run all tests simultaneously instead of sequentially
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
