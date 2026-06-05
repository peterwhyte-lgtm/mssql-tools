<#
Script Name : MultiServer-GetServiceStatus
Category    : multi-server-scripts/powershell
Purpose     : Check Windows service status across multiple remote hosts using Get-Service over RPC.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : RPC access to target hosts (port 135). Get-Service -ComputerName uses RPC, not WinRM.
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated hostnames or IPs.
              -ServiceName "SQL*"      Service name filter; wildcard supported. Default: SQL*.
              -Parallel                Run all servers simultaneously (PS7+).
              Note: no -Credential — Get-Service over RPC uses pass-through auth only.
Output      : Server, ServiceName, DisplayName, Status, StartType
Example     : .\MultiServer-GetServiceStatus.ps1 -Servers "SVR01,SVR02" -ServiceName MSSQLSERVER
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [string]$ServiceName = 'SQL*',
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
        try {
            $params = @{ Name = $sn; ComputerName = $srv; ErrorAction = 'Stop' }
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
