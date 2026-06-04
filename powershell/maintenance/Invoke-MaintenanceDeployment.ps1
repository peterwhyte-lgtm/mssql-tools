<#
.SYNOPSIS
Deploys the DBA maintenance job framework to one or more SQL Server instances.
Generates and applies backup jobs, index maintenance jobs, and housekeeping jobs
in a single orchestrated run.

.NOTES
ScriptType   : automation
TargetScope  : multi-server
RiskLevel    : MEDIUM
Purpose      : Scale out the maintenance framework to a fleet of servers without
               manually running the Generate-* scripts against each instance.
               Creates or replaces: DBA - Backup - FULL, DBA - Backup - LOG,
               DBA - Backup - Cleanup, DBA - Index Maintenance, DBA - Statistics Update,
               DBA - Integrity Check, DBA - History Cleanup, DBA - Cycle Error Log.

.DESCRIPTION
For each target server:
  1. Reads the SQL generator scripts (Generate-BackupJobs.sql, etc.)
  2. Substitutes the provided parameters into the DECLARE section
  3. Executes the generator to produce DDL
  4. Executes the DDL against the same server (splits on GO batches)
  5. Reports success or failure per server

Jobs are created idempotent — existing DBA jobs are dropped and recreated.

.PARAMETER Servers
Comma-separated list of SQL Server instances to deploy to.

.PARAMETER ServersFile
Path to a plain-text file with one SQL Server instance per line (overrides -Servers).

.PARAMETER Mode
Which job group to deploy. Default: All.
  All         — backup jobs + index maintenance + housekeeping
  Backup      — full backup, log backup, cleanup jobs only
  Index       — index maintenance and statistics update only
  Maintenance — integrity check, history cleanup, cycle error log only

.PARAMETER BackupRootPath
Backup destination folder on the target server. Default: D:\SQLBackups.

.PARAMETER FullRetentionDays
Days to keep full backup files. Default: 14.

.PARAMETER LogRetentionHours
Hours to keep log backup files. Default: 48.

.PARAMETER FullScheduleHour
Hour (0-23) for the daily full backup. Default: 2.

.PARAMETER LogIntervalMins
Log backup frequency in minutes. Default: 15.

.PARAMETER JobOwner
Login that owns the agent jobs. Default: sa.

.PARAMETER Username
SQL login for target instances. Omit for Windows auth.

.PARAMETER Password
SQL login password.

.PARAMETER FragReorgThreshold
Fragmentation percentage at which indexes are reorganized. Default: 10.0.

.PARAMETER FragRebuildThreshold
Fragmentation percentage at which indexes are rebuilt. Default: 30.0.

.PARAMETER MinPageCount
Minimum page count for an index to be considered for maintenance. Default: 1000.

.PARAMETER WhatIf
Show which servers would be targeted without deploying anything.

.EXAMPLE
# Deploy to three servers with default settings
.\powershell\maintenance\Invoke-MaintenanceDeployment.ps1 `
    -Servers "PROD01,PROD02,PROD03" -BackupRootPath "D:\SQLBackups"

.EXAMPLE
# Deploy from a servers file, custom backup path and retention
.\powershell\maintenance\Invoke-MaintenanceDeployment.ps1 `
    -ServersFile .\servers.txt `
    -BackupRootPath "\\BACKUPSRV\SQLBackups" `
    -FullRetentionDays 21 -LogRetentionHours 72 -Mode Backup

.EXAMPLE
# Preview — see which servers would be targeted without making changes
.\powershell\maintenance\Invoke-MaintenanceDeployment.ps1 `
    -Servers "PROD01,PROD02" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Servers,
    [string]$ServersFile,

    [ValidateSet('All', 'Backup', 'Index', 'Maintenance')]
    [string]$Mode              = 'All',

    [string]$BackupRootPath    = 'D:\SQLBackups',
    [int]$FullRetentionDays    = 14,
    [int]$LogRetentionHours    = 48,
    [int]$FullScheduleHour     = 2,
    [int]$LogIntervalMins      = 15,
    [string]$JobOwner          = 'sa',

    [decimal]$FragReorgThreshold   = 10.0,
    [decimal]$FragRebuildThreshold = 30.0,
    [int]$MinPageCount             = 1000,

    [string]$Username,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

# ── Server list resolution ────────────────────────────────────────────────────
$serverList = @()
if ($ServersFile) {
    if (-not (Test-Path $ServersFile)) { throw "ServersFile not found: $ServersFile" }
    $serverList = Get-Content $ServersFile | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') } |
                  ForEach-Object { $_.Trim() }
} elseif ($Servers) {
    $serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
} else {
    throw 'Provide -Servers or -ServersFile.'
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  DBA Maintenance Deployment' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Mode    : $Mode"
Write-Host "  Servers : $($serverList.Count)"
Write-Host "  Backup  : $BackupRootPath"
Write-Host ''

if ($WhatIfPreference) {
    Write-Host '[WhatIf] Would deploy to:' -ForegroundColor Yellow
    $serverList | ForEach-Object { Write-Host "  $_" }
    return
}

# ── Validate Invoke-Sqlcmd before touching any server ─────────────────────────
if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
    $sqlModule = Get-Module -Name SqlServer -ListAvailable
    if ($sqlModule) {
        Import-Module SqlServer -ErrorAction Stop
    } else {
        throw 'Invoke-Sqlcmd not available. Install the SqlServer module: Install-Module -Name SqlServer -Scope CurrentUser -Force'
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# ── Parameter substitution helper ────────────────────────────────────────────
function Set-SqlDeclare {
    param([string]$Sql, [string]$Param, $Value)
    if ($Value -is [string]) {
        $escaped = $Value -replace "'", "''"
        return $Sql -replace "(?m)(DECLARE\s+@$Param\s+\S+\s*=\s*)N'[^']*'", "`${1}N'$escaped'"
    } else {
        return $Sql -replace "(?m)(DECLARE\s+@$Param\s+\S+\s*=\s*)\d+\.?\d*", "`${1}$Value"
    }
}

# ── DDL execution helper (splits on GO batches) ───────────────────────────────
function Invoke-DdlBatches {
    param([string]$Server, [string]$Ddl)

    $batches = [regex]::Split($Ddl, '(?im)^\s*GO\s*$') |
               Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^\s*USE\s+msdb\s*;\s*$' }

    $sqlParams = @{
        ServerInstance         = $Server
        Database               = 'msdb'
        TrustServerCertificate = $true
        QueryTimeout           = 300
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) {
        $sqlParams['Username'] = $Username
        $sqlParams['Password'] = $Password
    }

    foreach ($batch in $batches) {
        Invoke-Sqlcmd @sqlParams -Query $batch
    }
}

# ── Execute a generator SQL and return the DDL output ─────────────────────────
function Get-GeneratedDdl {
    param([string]$Server, [string]$SqlContent)

    $genParams = @{
        ServerInstance         = $Server
        Database               = 'master'
        Query                  = $SqlContent
        MaxCharLength          = 2000000
        TrustServerCertificate = $true
        QueryTimeout           = 120
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) {
        $genParams['Username'] = $Username
        $genParams['Password'] = $Password
    }

    $result = Invoke-Sqlcmd @genParams
    return $result.ddl
}

# ── Load and parameterise generator scripts ───────────────────────────────────
$generators = @{}

if ($Mode -in 'All', 'Backup') {
    $sql = Get-Content (Join-Path $repoRoot 'sql\maintenance\Generate-BackupJobs.sql') -Raw
    $sql = Set-SqlDeclare $sql 'BackupRootPath'    $BackupRootPath
    $sql = Set-SqlDeclare $sql 'FullRetentionDays' $FullRetentionDays
    $sql = Set-SqlDeclare $sql 'LogRetentionHours' $LogRetentionHours
    $sql = Set-SqlDeclare $sql 'FullScheduleHour'  $FullScheduleHour
    $sql = Set-SqlDeclare $sql 'LogIntervalMins'   $LogIntervalMins
    $sql = Set-SqlDeclare $sql 'JobOwner'           $JobOwner
    $generators['backup'] = $sql
}

if ($Mode -in 'All', 'Index') {
    $sql = Get-Content (Join-Path $repoRoot 'sql\maintenance\Generate-IndexMaintenanceJobs.sql') -Raw
    $sql = Set-SqlDeclare $sql 'JobOwner'              $JobOwner
    $sql = Set-SqlDeclare $sql 'FragReorgThreshold'    $FragReorgThreshold
    $sql = Set-SqlDeclare $sql 'FragRebuildThreshold'  $FragRebuildThreshold
    $sql = Set-SqlDeclare $sql 'MinPageCount'          $MinPageCount
    $generators['index'] = $sql
}

if ($Mode -in 'All', 'Maintenance') {
    $sql = Get-Content (Join-Path $repoRoot 'sql\maintenance\Generate-MaintenanceJobs.sql') -Raw
    $sql = Set-SqlDeclare $sql 'JobOwner' $JobOwner
    $generators['maintenance'] = $sql
}

# ── Deploy ────────────────────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[PSObject]]::new()

foreach ($server in $serverList) {
    Write-Host "  Deploying to $server ..." -NoNewline
    $serverResult = [PSCustomObject]@{ Server = $server; Status = ''; Detail = '' }

    try {
        foreach ($genKey in $generators.Keys) {
            $ddl = Get-GeneratedDdl -Server $server -SqlContent $generators[$genKey]
            if (-not $ddl -or $ddl.Trim() -eq '') {
                throw "Generator '$genKey' returned empty DDL from $server"
            }
            Invoke-DdlBatches -Server $server -Ddl $ddl
        }

        $serverResult.Status = 'OK'
        $serverResult.Detail = "$($generators.Count) job group(s) deployed"
        Write-Host " OK" -ForegroundColor Green

    } catch {
        $serverResult.Status = 'FAILED'
        $serverResult.Detail = $_.Exception.Message -replace "`r?`n", ' '
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    $($serverResult.Detail)" -ForegroundColor DarkRed
    }

    $results.Add($serverResult)
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '--------------------------------------------'
$ok     = @($results | Where-Object Status -eq 'OK').Count
$failed = @($results | Where-Object Status -eq 'FAILED').Count
Write-Host "  OK: $ok  |  Failed: $failed" -ForegroundColor Cyan
if ($failed -gt 0) {
    Write-Host ''
    Write-Host '  Failed servers:' -ForegroundColor Red
    $results | Where-Object Status -eq 'FAILED' |
        ForEach-Object { Write-Host "    $($_.Server): $($_.Detail)" -ForegroundColor DarkRed }
}
Write-Host ''
Write-Host "  Verify with: .\tools\multi-server-scripts\sql\MultiServer-GetMaintenanceJobStatus.ps1 -Servers `"$Servers`"" -ForegroundColor DarkGray
Write-Host ''
