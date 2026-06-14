<#
Script Name : MultiServer-GetMaintenanceJobStatus
Category    : multi-server-scripts/sql
Purpose     : Checks whether DBA maintenance jobs (DBA - Backup - FULL, DBA - Backup - LOG,
              DBA - Index Maintenance, etc.) are deployed and have run successfully across
              multiple SQL Server instances. Use after deploying the maintenance framework
              to verify coverage and catch silent failures.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : SqlServer PowerShell module.
              Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated SQL Server instances.
              -SqlAuth                  Prompt for SQL credentials instead of Windows auth.
              -Parallel                 Run all servers simultaneously (PS7+).
              -OutCsv path.csv         Save full results to CSV.
              -FailedOnly              Only show jobs that failed or are missing.
Output      : server, job_name, status, last_run_status, last_run_at, last_run_duration,
              next_run_at
Example     : .\MultiServer-GetMaintenanceJobStatus.ps1 -Servers "SVR01,SVR02" -FailedOnly
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [switch]$SqlAuth,
    [switch]$Parallel,
    [switch]$FailedOnly,
    [string]$OutCsv
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
SELECT
    j.name AS job_name,
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS status,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 4 THEN 'In Progress'
        ELSE        'Never run'
    END AS last_run_status,
    CASE WHEN h.run_date IS NULL THEN NULL
         ELSE msdb.dbo.agent_datetime(h.run_date, h.run_time)
    END AS last_run_at,
    CASE WHEN h.run_duration IS NULL THEN NULL
         ELSE RIGHT('0' + CAST(h.run_duration / 10000 AS varchar(4)), 2) + ':'
            + RIGHT('0' + CAST((h.run_duration % 10000) / 100 AS varchar(2)), 2) + ':'
            + RIGHT('0' + CAST(h.run_duration % 100 AS varchar(2)), 2)
    END AS last_run_duration,
    CASE WHEN sch.next_run_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(sch.next_run_date, sch.next_run_time)
    END AS next_run_at
FROM msdb.dbo.sysjobs j
OUTER APPLY (
    SELECT TOP 1 h.run_date, h.run_time, h.run_duration, h.run_status
    FROM msdb.dbo.sysjobhistory h
    WHERE h.job_id = j.job_id AND h.step_id = 0
    ORDER BY h.run_date DESC, h.run_time DESC
) h
OUTER APPLY (
    SELECT TOP 1 s.next_run_date, s.next_run_time
    FROM msdb.dbo.sysjobschedules js
    JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
    WHERE js.job_id = j.job_id AND s.enabled = 1
      AND (s.next_run_date > 0 OR s.next_run_time > 0)
    ORDER BY s.next_run_date, s.next_run_time
) sch
WHERE j.name LIKE N'DBA - %'
ORDER BY j.name;
"@

$expectedJobs = @(
    'DBA - Backup - FULL'
    'DBA - Backup - LOG'
    'DBA - Backup - Cleanup'
    'DBA - Index Maintenance'
    'DBA - Statistics Update'
    'DBA - Integrity Check'
    'DBA - History Cleanup'
    'DBA - Cycle Error Log'
)

function Get-JobStatus([string]$server) {
    try {
        $params = @{
            ServerInstance         = $server
            Database               = 'msdb'
            Query                  = $sql
            TrustServerCertificate = $true
            OutputAs               = 'DataTables'
            ErrorAction            = 'Stop'
        }
        if ($credential) {
            $params.Username = $credential.UserName
            $params.Password = $credential.GetNetworkCredential().Password
        }
        $rows = @(Invoke-Sqlcmd @params)
        $found = $rows | Select-Object -ExpandProperty job_name

        # Synthesize a NOT DEPLOYED row for expected but missing jobs
        $missing = $expectedJobs | Where-Object { $_ -notin $found } | ForEach-Object {
            [PSCustomObject]@{ job_name = $_; status = 'NOT DEPLOYED'; last_run_status = 'N/A'
                               last_run_at = $null; last_run_duration = ''; next_run_at = $null }
        }

        @($rows) + @($missing) | ForEach-Object { $_ | Select-Object *, @{n='Server'; e={ $server }} }
    } catch {
        [PSCustomObject]@{
            Server = $server; job_name = 'ERROR'; status = 'ERROR'
            last_run_status = $_.Exception.Message; last_run_at = $null
            last_run_duration = ''; next_run_at = $null
        }
    }
}

$allResults = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        Import-Module SqlServer -ErrorAction SilentlyContinue
        $srv = $_; $q = $using:sql; $cr = $using:credential; $exp = $using:expectedJobs
        try {
            $p = @{ ServerInstance = $srv; Database = 'msdb'; Query = $q;
                    TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
            if ($cr) { $p.Username = $cr.UserName; $p.Password = $cr.GetNetworkCredential().Password }
            $rows = @(Invoke-Sqlcmd @p)
            $found = $rows | Select-Object -ExpandProperty job_name
            $missing = $exp | Where-Object { $_ -notin $found } | ForEach-Object {
                [PSCustomObject]@{ job_name = $_; status = 'NOT DEPLOYED'; last_run_status = 'N/A'
                                   last_run_at = $null; last_run_duration = ''; next_run_at = $null }
            }
            @($rows) + @($missing) | ForEach-Object { $_ | Select-Object *, @{n='Server'; e={ $srv }} }
        } catch {
            [PSCustomObject]@{ Server = $srv; job_name = 'ERROR'; status = 'ERROR'
                               last_run_status = $_.Message; last_run_at = $null
                               last_run_duration = ''; next_run_at = $null }
        }
    } -ThrottleLimit 10 | ForEach-Object { $allResults.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n=== $server ===" -ForegroundColor Cyan
        $rows = @(Get-JobStatus $server)
        foreach ($r in $rows) { $allResults.Add($r) }
        if ($FailedOnly) { $rows = $rows | Where-Object { $_.status -in 'NOT DEPLOYED','Disabled' -or $_.last_run_status -eq 'Failed' } }
        $rows | Format-Table job_name, status, last_run_status, last_run_at, last_run_duration -AutoSize
    }
}

if ($Parallel -and $allResults.Count -gt 0) {
    $display = if ($FailedOnly) {
        $allResults | Where-Object { $_.status -in 'NOT DEPLOYED','Disabled' -or $_.last_run_status -eq 'Failed' }
    } else { $allResults }
    Write-Host "`n── Maintenance job summary ──────────────────────────────" -ForegroundColor DarkGray
    $display | Sort-Object Server, job_name |
        Format-Table Server, job_name, status, last_run_status, last_run_at -AutoSize
}

if ($OutCsv -and $allResults.Count -gt 0) {
    $allResults | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Saved to $OutCsv" -ForegroundColor Green
}

# Summary counts
$notDeployed = @($allResults | Where-Object { $_.status -eq 'NOT DEPLOYED' }).Count
$failed      = @($allResults | Where-Object { $_.last_run_status -eq 'Failed' }).Count
$disabled    = @($allResults | Where-Object { $_.status -eq 'Disabled' }).Count
if ($notDeployed -gt 0) { Write-Host "  NOT DEPLOYED: $notDeployed job(s)" -ForegroundColor Yellow }
if ($failed      -gt 0) { Write-Host "  FAILED      : $failed job(s)" -ForegroundColor Red }
if ($disabled    -gt 0) { Write-Host "  DISABLED    : $disabled job(s)" -ForegroundColor Yellow }
Write-Host "`nDone." -ForegroundColor Green
