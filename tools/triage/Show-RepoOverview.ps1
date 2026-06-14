<#
.SYNOPSIS
Prints a descriptive overview of the DBA scripts repo — intended as the first
thing a new user runs to understand what's here and how to get started.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

$sqlDesc = @{
    'performance' = 'Wait stats, blocking, long queries, missing indexes, I/O, plan cache'
    'monitoring'  = 'DB health, memory, MAXDOP, jobs, AG, TempDB, DBCC, suspect pages'
    'backups'     = 'Backup coverage, history, DR estimates, restore script generation'
    'security'    = 'Roles, permissions, orphans, weak logins, xp_cmdshell surface area'
    'migration'   = 'DB/login/job/linked-server inventory for instance migrations'
    'lab'         = 'Test and development scripts — not for production use'
}

$psDesc = @{
    'reporting'          = 'Perf wrappers + Invoke-HealthCheckCollection + Review-HealthCheckOutput'
    'inventory'          = 'Storage, growth, disk space, instance configuration snapshots'
    'health-checks'      = 'DBCC, suspect pages, TempDB hotspots, integrity pre-checks'
    'backup-automation'  = 'Backup and restore execution, history wrappers'
    'security'           = 'Wrappers for all sql/security/ scripts'
    'migration'          = 'Wrappers for sql/migration/ scripts + DDL generators (logins, jobs)'
    'lab'                = 'Test and development scripts — not for production use'
}

function Show-CategoryTable {
    param(
        [string]$Label,
        [string]$RootPath,
        [string]$Extension,
        [hashtable]$Descriptions
    )
    if (-not (Test-Path $RootPath)) { return }

    $dirs  = Get-ChildItem -Path $RootPath -Directory | Sort-Object Name
    $total = 0
    $rows  = foreach ($dir in $dirs) {
        $count = @(Get-ChildItem -Path $dir.FullName -File -Filter "*.$Extension" -ErrorAction SilentlyContinue).Count
        $total += $count
        [PSCustomObject]@{
            Category    = $dir.Name
            Count       = $count
            Description = if ($Descriptions.ContainsKey($dir.Name)) { $Descriptions[$dir.Name] } else { '' }
        }
    }

    Write-Host ""
    Write-Host "  $Label  ($total scripts)" -ForegroundColor Cyan
    Write-Host ("  " + [string]::new('-', 68)) -ForegroundColor DarkCyan
    foreach ($row in $rows) {
        $cat = $row.Category.PadRight(22)
        $cnt = "$($row.Count)".PadLeft(3)
        Write-Host "  $cat $cnt  " -NoNewline -ForegroundColor Yellow
        Write-Host $row.Description -ForegroundColor Gray
    }
}

# ── Header ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ([string]::new('=', 72)) -ForegroundColor DarkCyan
Write-Host "  DBA Scripts  —  SQL Server Toolkit                    sqldba.blog" -ForegroundColor Cyan
Write-Host ([string]::new('=', 72)) -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  A production SQL Server DBA toolkit covering diagnostics, healthchecks,"
Write-Host "  security audits, and migration inventory. All SQL scripts are read-only."
Write-Host ""
Write-Host "  Run any script by name (fuzzy match, no path needed):" -ForegroundColor DarkGray
Write-Host "    .\run.ps1 Get-WaitStatistics" -ForegroundColor White
Write-Host "    .\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019" -ForegroundColor White
Write-Host ""
Write-Host "  Set a target server once for the whole session:" -ForegroundColor DarkGray
Write-Host "    .\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01" -ForegroundColor White

# ── Category tables ──────────────────────────────────────────────────────────
Show-CategoryTable -Label 'SQL Scripts'        -RootPath (Join-Path $repoRoot 'database-admin\sql-scripts')        -Extension 'sql' -Descriptions $sqlDesc
Show-CategoryTable -Label 'PowerShell Scripts' -RootPath (Join-Path $repoRoot 'database-admin\powershell-scripts') -Extension 'ps1' -Descriptions $psDesc

# ── Recommended next steps ───────────────────────────────────────────────────
Write-Host ""
Write-Host ([string]::new('=', 72)) -ForegroundColor DarkCyan
Write-Host "  Recommended First Steps" -ForegroundColor Cyan
Write-Host ([string]::new('=', 72)) -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  [1]  Verify you can connect to SQL Server" -ForegroundColor Green
Write-Host "       .\tools\local-sql\Test-SqlConnectivity.ps1 -ServerInstance ." -ForegroundColor White
Write-Host ""
Write-Host "  [2]  Run a full healthcheck (collects 19 scripts, surfaces CRITICAL/WARNING)" -ForegroundColor Green
Write-Host "       .\database-admin\powershell-scripts\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance ." -ForegroundColor White
Write-Host "       .\database-admin\powershell-scripts\reporting\Review-HealthCheckOutput.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  [3]  Quick performance diagnostics" -ForegroundColor Green
Write-Host "       .\run.ps1 Get-WaitStatistics" -ForegroundColor White
Write-Host "       .\run.ps1 Get-LongRunningQueries" -ForegroundColor White
Write-Host "       .\run.ps1 Get-BackupCoverage" -ForegroundColor White
Write-Host ""
Write-Host "  [4]  Find scripts by keyword" -ForegroundColor Green
Write-Host "       .\tools\triage\Find-UsefulScript.ps1 -Keyword blocking" -ForegroundColor White
Write-Host ""
Write-Host "  [5]  Browse the full structure" -ForegroundColor Green
Write-Host "       database-admin/sql-scripts/        — SSMS-ready diagnostic queries (run directly or via .\run.ps1)" -ForegroundColor White
Write-Host "       database-admin/powershell-scripts/ — wrappers, healthcheck collection, automation" -ForegroundColor White
Write-Host "       database-admin/migration/          — migration DDL generators and assessment scripts" -ForegroundColor White
Write-Host "       docs/ops/    — change orders, runbooks, checklists, rollback playbooks" -ForegroundColor White
Write-Host "       docs/        — structure notes, standards, roadmap" -ForegroundColor White
Write-Host ""
