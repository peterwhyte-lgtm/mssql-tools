<#
Script Name : MultiServer-GetWaitStats
Category    : multi-server-queries/sql
Purpose     : Run wait statistics against multiple SQL Server instances and display
              the top wait types ranked by percentage of total wait time.
              SQL is embedded inline — no dependency on the repo at runtime.
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : SqlServer PowerShell module.
              Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force
              Port 1433 (or custom SQL port) must be accessible from this machine.

Parameters:
  -Servers    Required. Comma-separated SQL Server instances: "SVR01,SVR02\INST01"
  -Database   Target database for the connection. Default: master.
  -Top        How many wait types to show per server. Default: 10.
  -SqlAuth    Switch. Prompt for SQL Server credentials instead of Windows auth.
  -Parallel   Run against all servers simultaneously (PS7+). Default: sequential.

Usage examples:
  # Wait stats across three servers, Windows auth
  .\MultiServer-GetWaitStats.ps1 -Servers "SVR01,SVR02,SVR03"

  # Top 5 waits, SQL auth
  .\MultiServer-GetWaitStats.ps1 -Servers "SVR01,SVR02" -Top 5 -SqlAuth

  # Parallel sweep
  .\MultiServer-GetWaitStats.ps1 -Servers "SVR01,SVR02,SVR03,SVR04" -Parallel
#>

[CmdletBinding()]
param (
    # Comma-separated SQL Server instance names — include instance name if not default
    [Parameter(Mandatory)]
    [string]$Servers,

    # Target database for the SQL connection. Default: master.
    [string]$Database = 'master',

    # Number of top wait types to show per server
    [int]$Top = 10,

    # Use SQL authentication instead of Windows auth — prompts for credentials
    [switch]$SqlAuth,

    # Run against all servers simultaneously (PS7+). Sequential is default.
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -Name SqlServer -ListAvailable)) {
    Write-Host ''
    Write-Host '  The SqlServer module is required.' -ForegroundColor Yellow
    Write-Host '  Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force' -ForegroundColor Cyan
    Write-Host ''
    exit 1
}

Import-Module SqlServer -ErrorAction Stop

$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

$credential = $null
if ($SqlAuth) {
    $credential = Get-Credential -Message "SQL Server credentials for: $($serverList -join ', ')"
}

$sql = @"
WITH filtered_waits AS (
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0
      AND wait_type NOT IN (
          'SLEEP_TASK','SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SLEEP_DBSTARTUP',
          'SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY',
          'SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP','SNI_HTTP_ACCEPT',
          'DISPATCHER_QUEUE_SEMAPHORE','BROKER_TO_FLUSH','BROKER_TASK_STOP',
          'BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','CHECKPOINT_QUEUE',
          'DBMIRROR_EVENTS_QUEUE','DBMIRROR_WORKER_QUEUE',
          'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_BUFFER_FLUSH',
          'SQLTRACE_WAIT_ENTRIES','WAITFOR','LAZYWRITER_SLEEP','LOGMGR_QUEUE',
          'ONDEMAND_TASK_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE',
          'SERVER_IDLE_CHECK','SP_SERVER_DIAGNOSTICS_SLEEP',
          'WAIT_XTP_OFFLINE_CKPT_NEW_LOG','XE_DISPATCHER_WAIT','XE_TIMER_EVENT',
          'HADR_WORK_QUEUE','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
          'HADR_CLUSAPI_CALL','HADR_NOTIFICATION_DEQUEUE',
          'FT_IFTS_SCHEDULER_IDLE_WAIT','FT_IFTSHC_MUTEX',
          'REPL_WORK_QUEUE','CLR_AUTO_EVENT','CLR_MANUAL_EVENT','WAIT_XTP_COMPILE_WAIT'
      )
)
SELECT TOP $Top
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(5,2)) AS pct_total_wait,
    CAST(wait_time_ms / NULLIF(waiting_tasks_count, 0) AS DECIMAL(10,0))              AS avg_wait_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    resource_wait_time_ms
FROM filtered_waits
ORDER BY wait_time_ms DESC;
"@

function Invoke-WaitStats([string]$server) {
    try {
        $params = @{
            ServerInstance      = $server
            Database            = $Database
            Query               = $sql
            TrustServerCertificate = $true
            OutputAs            = 'DataTables'
            ErrorAction         = 'Stop'
        }
        if ($credential) {
            $params.Username = $credential.UserName
            $params.Password = $credential.GetNetworkCredential().Password
        }
        $results = Invoke-Sqlcmd @params
        if ($results) {
            foreach ($row in $results) {
                $row | Select-Object *, @{n='Server'; e={ $server }}
            }
        }
    } catch {
        [PSCustomObject]@{ Server = $server; wait_type = 'ERROR'; pct_total_wait = 0; avg_wait_ms = 0; Error = $_.Exception.Message }
    }
}

$allResults = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    # Parallel Invoke-Sqlcmd — each server in its own thread
    $serverList | ForEach-Object -Parallel {
        Import-Module SqlServer -ErrorAction SilentlyContinue
        $srv = $_
        $q   = $using:sql
        $db  = $using:Database
        $cr  = $using:credential
        try {
            $p = @{ ServerInstance = $srv; Database = $db; Query = $q; TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
            if ($cr) { $p.Username = $cr.UserName; $p.Password = $cr.GetNetworkCredential().Password }
            $rows = Invoke-Sqlcmd @p
            foreach ($r in $rows) { $r | Select-Object *, @{n='Server'; e={ $srv }} }
        } catch {
            [PSCustomObject]@{ Server = $srv; wait_type = 'ERROR'; pct_total_wait = 0; avg_wait_ms = 0; Error = $_.Message }
        }
    } -ThrottleLimit 10 | ForEach-Object { $allResults.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n=== $server ===" -ForegroundColor Cyan
        $rows = @(Invoke-WaitStats $server)
        foreach ($r in $rows) { $allResults.Add($r) }
        $rows | Format-Table wait_type, pct_total_wait, avg_wait_ms, wait_time_ms, waiting_tasks_count -AutoSize
    }
}

if ($Parallel -and $allResults.Count -gt 0) {
    Write-Host "`n── All results (sorted by server, then wait %) ──────────" -ForegroundColor DarkGray
    $allResults | Sort-Object Server, { [double]$_.pct_total_wait } -Descending |
        Format-Table Server, wait_type, pct_total_wait, avg_wait_ms, wait_time_ms -AutoSize
}

Write-Host "`nDone." -ForegroundColor Green
