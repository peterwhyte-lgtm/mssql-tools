<#
Script Name : MultiServer-GetServiceStatus
Category    : multi-server-queries/powershell
Purpose     : Check the status of Windows services across multiple remote hosts.
              Useful for confirming services are running after a restart, failover,
              or patch cycle, or for auditing service state across an estate.
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : WinRM enabled on target hosts, or admin share access (Get-Service -ComputerName
              uses RPC, not WinRM, so WinRM is not strictly required for this script).

Parameters:
  -Servers       Required. Comma-separated hostnames or IPs: "SVR01,SVR02,SVR03"
  -ServiceName   Optional filter. Wildcard supported. Default: SQL* (all SQL Server services).
                 Examples: "MSSQLSERVER", "SQL*", "W3SVC", "*"
  -Credential    Optional. PSCredential for alternate auth.
  -Parallel      Run against all servers simultaneously (PS7+). Default: sequential.

Usage examples:
  # Check all SQL services across three servers
  .\MultiServer-GetServiceStatus.ps1 -Servers "SVR01,SVR02,SVR03"

  # Check a specific service on multiple servers
  .\MultiServer-GetServiceStatus.ps1 -Servers "SVR01,SVR02" -ServiceName MSSQLSERVER

  # Check all services (use with caution on servers with many services)
  .\MultiServer-GetServiceStatus.ps1 -Servers "SVR01,SVR02" -ServiceName "*"
#>

[CmdletBinding()]
param (
    # Comma-separated list of target hostnames or IPs
    [Parameter(Mandatory)]
    [string]$Servers,

    # Service name filter — wildcard supported. Default SQL* returns all SQL Server services.
    [string]$ServiceName = 'SQL*',

    # Alternate credentials — omit to use current Windows identity
    [PSCredential]$Credential,

    # Run against all servers simultaneously (PS7+). Sequential is default.
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

if ($serverList.Count -eq 0) {
    Write-Error "-Servers contained no valid hostnames."
    exit 1
}

$results = [System.Collections.Generic.List[object]]::new()

function Get-ServicesFromHost([string]$server) {
    try {
        $params = @{ Name = $ServiceName; ComputerName = $server; ErrorAction = 'Stop' }
        if ($Credential) { $params.Credential = $Credential }
        $svcs = Get-Service @params
        foreach ($s in $svcs) {
            [PSCustomObject]@{
                Server      = $server
                ServiceName = $s.Name
                DisplayName = $s.DisplayName
                Status      = $s.Status
                StartType   = $s.StartType
                Error       = ''
            }
        }
    } catch {
        [PSCustomObject]@{
            Server      = $server
            ServiceName = $ServiceName
            DisplayName = ''
            Status      = 'ERROR'
            StartType   = ''
            Error       = $_.Exception.Message
        }
    }
}

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv = $_
        $sn  = $using:ServiceName
        $cr  = $using:Credential
        try {
            $params = @{ Name = $sn; ComputerName = $srv; ErrorAction = 'Stop' }
            if ($cr) { $params.Credential = $cr }
            $svcs = Get-Service @params
            foreach ($s in $svcs) {
                [PSCustomObject]@{ Server = $srv; ServiceName = $s.Name; DisplayName = $s.DisplayName; Status = $s.Status; StartType = $s.StartType; Error = '' }
            }
        } catch {
            [PSCustomObject]@{ Server = $srv; ServiceName = $sn; DisplayName = ''; Status = 'ERROR'; StartType = ''; Error = $_.Message }
        }
    } -ThrottleLimit 10 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n→ $server" -ForegroundColor Cyan
        $rows = Get-ServicesFromHost $server
        foreach ($r in $rows) {
            $clr = switch ($r.Status) { 'Running' { 'Green' } 'Stopped' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
            Write-Host ("  [{0,-8}] {1}" -f $r.Status, $r.DisplayName) -ForegroundColor $clr
            $results.Add($r)
        }
    }
}

Write-Host "`n── All results ──────────────────────────────────────────" -ForegroundColor DarkGray
$results | Sort-Object Server, ServiceName | Format-Table Server, ServiceName, Status, StartType, DisplayName, Error -AutoSize
