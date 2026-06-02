<#
Script Name : MultiServer-GetRecentEventLogs
Category    : multi-server-queries/powershell
Purpose     : Pull recent Error and Warning events from Windows Event Logs on multiple
              remote hosts. Useful for post-incident triage, patch validation, or routine
              estate health checks.
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : Remote Event Log access on target hosts (uses RPC — WinRM not required).
              The RemoteRegistry service must be running on target hosts.

Parameters:
  -Servers       Required. Comma-separated hostnames or IPs: "SVR01,SVR02,SVR03"
  -LogName       Which log(s) to read. Default: Application, System.
                 Pass multiple as comma-separated: "Application,System,Security"
  -Level         Event severity to include. Default: Error, Warning.
                 Options: Error | Warning | Information | Critical (comma-separated).
  -Hours         How many hours back to look. Default: 24.
  -MaxPerServer  Maximum events to return per server per log. Default: 50.
  -Credential    Optional. PSCredential for alternate auth.
  -Parallel      Run against all servers simultaneously (PS7+). Default: sequential.

Usage examples:
  # Last 24h errors and warnings from Application and System logs on three servers
  .\MultiServer-GetRecentEventLogs.ps1 -Servers "SVR01,SVR02,SVR03"

  # Last 48h errors only, Application log
  .\MultiServer-GetRecentEventLogs.ps1 -Servers "SVR01,SVR02" -Level Error -Hours 48 -LogName Application

  # Last 6h — quick post-restart check
  .\MultiServer-GetRecentEventLogs.ps1 -Servers "SVR01,SVR02,SVR03" -Hours 6
#>

[CmdletBinding()]
param (
    # Comma-separated list of target hostnames or IPs
    [Parameter(Mandatory)]
    [string]$Servers,

    # Event log(s) to read — comma-separated: "Application,System"
    [string]$LogName = 'Application,System',

    # Event levels to include — comma-separated: "Error,Warning"
    [string]$Level = 'Error,Warning',

    # How many hours back to look for events
    [int]$Hours = 24,

    # Maximum events returned per server per log (avoids overwhelming output)
    [int]$MaxPerServer = 50,

    # Alternate credentials — omit to use current Windows identity
    [PSCredential]$Credential,

    # Run against all servers simultaneously (PS7+). Sequential is default.
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$logNames   = $LogName -split ','  | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

# Map string level names to WinEvent level values
$levelMap = @{ Error=2; Warning=3; Information=4; Critical=1 }
$levelNums = $Level -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
    if ($levelMap.ContainsKey($_)) { $levelMap[$_] } else { Write-Warning "Unknown level '$_' — skipping"; $null }
} | Where-Object { $null -ne $_ }

if ($levelNums.Count -eq 0) {
    Write-Error "No valid event levels specified. Use Error, Warning, Information, or Critical."
    exit 1
}

$since = (Get-Date).AddHours(-$Hours)

$results = [System.Collections.Generic.List[object]]::new()

function Get-EventsFromHost([string]$server) {
    foreach ($log in $logNames) {
        try {
            $filter = @{
                LogName   = $log
                Level     = $levelNums
                StartTime = $since
            }
            $params = @{ FilterHashtable = $filter; MaxEvents = $MaxPerServer; ErrorAction = 'Stop' }
            if ($server -ne '.') { $params.ComputerName = $server }
            if ($Credential)     { $params.Credential   = $Credential }

            $events = Get-WinEvent @params -ErrorAction SilentlyContinue
            foreach ($e in $events) {
                [PSCustomObject]@{
                    Server    = $server
                    Log       = $log
                    TimeUtc   = $e.TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
                    Level     = $e.LevelDisplayName
                    Source    = $e.ProviderName
                    EventId   = $e.Id
                    Message   = ($e.Message -split "`n")[0].Trim()  # first line only
                    Error     = ''
                }
            }
        } catch [System.Exception] {
            if ($_.Exception.Message -match 'No events') { continue }
            [PSCustomObject]@{
                Server = $server; Log = $log; TimeUtc = ''; Level = 'ERROR'; Source = '';
                EventId = 0; Message = $_.Exception.Message; Error = $_.Exception.Message
            }
        }
    }
}

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv   = $_
        $logs  = $using:logNames
        $lvls  = $using:levelNums
        $since = $using:since
        $max   = $using:MaxPerServer
        $cr    = $using:Credential
        foreach ($log in $logs) {
            try {
                $filter = @{ LogName = $log; Level = $lvls; StartTime = $since }
                $params = @{ FilterHashtable = $filter; MaxEvents = $max; ErrorAction = 'SilentlyContinue' }
                if ($srv -ne '.') { $params.ComputerName = $srv }
                if ($cr)          { $params.Credential   = $cr }
                $events = Get-WinEvent @params
                foreach ($e in $events) {
                    [PSCustomObject]@{ Server = $srv; Log = $log; TimeUtc = $e.TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss');
                        Level = $e.LevelDisplayName; Source = $e.ProviderName; EventId = $e.Id;
                        Message = ($e.Message -split "`n")[0].Trim(); Error = '' }
                }
            } catch { }
        }
    } -ThrottleLimit 10 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n→ $server" -ForegroundColor Cyan
        $rows = @(Get-EventsFromHost $server)
        if ($rows.Count -eq 0) {
            Write-Host "  (no matching events in the last $Hours hours)" -ForegroundColor DarkGray
        } else {
            foreach ($r in $rows) {
                $clr = switch ($r.Level) { 'Error' { 'Red' } 'Critical' { 'Magenta' } 'Warning' { 'Yellow' } default { 'Gray' } }
                Write-Host ("  [{0}] {1}  {2} #{3}  {4}" -f $r.Level, $r.TimeUtc, $r.Source, $r.EventId, $r.Message.Substring(0, [Math]::Min(80, $r.Message.Length))) -ForegroundColor $clr
                $results.Add($r)
            }
        }
    }
}

if ($results.Count -gt 0) {
    Write-Host "`n── All events ───────────────────────────────────────────" -ForegroundColor DarkGray
    $results | Sort-Object Server, TimeUtc -Descending |
        Format-Table Server, Log, TimeUtc, Level, Source, EventId, Message -AutoSize
} else {
    Write-Host "`nNo matching events found on any server in the last $Hours hours." -ForegroundColor Green
}
