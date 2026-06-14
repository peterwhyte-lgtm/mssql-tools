<#
.SYNOPSIS
Captures a performance and configuration baseline snapshot for pre/post migration comparison.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE

.DESCRIPTION
Saves key performance and configuration CSVs to output-files\migration\baseline\<label>-<server>-<timestamp>\.

Run with -Label pre against the source server before migration.
Run with -Label post against the target server after cutover.
Compare matching CSV files to identify configuration gaps or performance regressions.

Key comparison points:
  - server-info       confirms target version is as expected
  - instance-config   confirms sp_configure settings match (MAXDOP, max memory, etc.)
  - wait-stats        identifies new dominant wait types post-migration
  - io-usage          confirms read/write latency is not worse on new storage
  - database-sizes    confirms all databases migrated with expected sizes
  - ag-state          confirms AG is synchronised (if applicable)

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Label
Snapshot label — 'pre' for the source server before migration, 'post' for the target after cutover.

.PARAMETER OutputRoot
Parent folder for baseline output. Defaults to output-files\migration\baseline under the repo root.

.EXAMPLE
.\database-admin\migration\powershell\Export-MigrationBaseline.ps1 -ServerInstance PROD01\SQL2019 -Label pre

.EXAMPLE
.\database-admin\migration\powershell\Export-MigrationBaseline.ps1 -ServerInstance PROD02\SQL2022 -Label post
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('pre', 'post')]
    [string]$Label = 'pre',
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$env:DBASCRIPTS_BATCH  = '1'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$runner   = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $runner)) { throw "Runner not found: $runner" }

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'output-files\migration\baseline'
}

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFolder = Join-Path $OutputRoot "$Label-$safeName-$timestamp"
New-Item -ItemType Directory -Path $outFolder -Force | Out-Null

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Migration Baseline Capture [$($Label.ToUpper())]" -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Server : $ServerInstance"
Write-Host "  Label  : $Label"
Write-Host "  Output : $outFolder"
Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host '--------------------------------------------'
Write-Host ''

$scripts = @(
    [PSCustomObject]@{ Label = 'server-info';      Path = 'database-admin\sql-scripts\monitoring\Get-VersionAndEdition.sql' }
    [PSCustomObject]@{ Label = 'os-hardware';      Path = 'database-admin\sql-scripts\monitoring\Get-OsAndHardwareInfo.sql' }
    [PSCustomObject]@{ Label = 'instance-config';  Path = 'database-admin\sql-scripts\monitoring\Get-InstanceConfigurationSnapshot.sql' }
    [PSCustomObject]@{ Label = 'memory-config';    Path = 'database-admin\sql-scripts\monitoring\Get-MemoryConfigurationAndUsage.sql' }
    [PSCustomObject]@{ Label = 'maxdop-config';    Path = 'database-admin\sql-scripts\monitoring\Get-MaxdopConfiguration.sql' }
    [PSCustomObject]@{ Label = 'database-health';  Path = 'database-admin\sql-scripts\monitoring\Get-DatabaseHealth.sql' }
    [PSCustomObject]@{ Label = 'database-sizes';   Path = 'database-admin\sql-scripts\monitoring\Get-DatabaseSizesAndFreeSpace.sql' }
    [PSCustomObject]@{ Label = 'database-files';   Path = 'database-admin\sql-scripts\monitoring\Get-DatabaseFilesDetail.sql' }
    [PSCustomObject]@{ Label = 'backup-coverage';  Path = 'database-admin\sql-scripts\backups\Get-BackupCoverage.sql' }
    [PSCustomObject]@{ Label = 'wait-stats';       Path = 'database-admin\sql-scripts\performance\Get-WaitStatistics.sql' }
    [PSCustomObject]@{ Label = 'io-usage';         Path = 'database-admin\sql-scripts\performance\Get-DatabaseIoUsage.sql' }
    [PSCustomObject]@{ Label = 'ag-state';         Path = 'database-admin\sql-scripts\ha-dr\Get-AvailabilityGroupReplicaState.sql' }
    [PSCustomObject]@{ Label = 'disk-space';       Path = 'database-admin\sql-scripts\monitoring\Get-DiskSpace.sql' }
)

$summary = [System.Collections.Generic.List[PSObject]]::new()

foreach ($s in $scripts) {
    $sqlPath = Join-Path $repoRoot $s.Path
    $csvPath = Join-Path $outFolder "$($s.Label).csv"
    $status  = 'OK'
    $note    = ''

    if (-not (Test-Path -LiteralPath $sqlPath)) {
        $status = 'SKIPPED'
        $note   = 'SQL file not found'
    }
    else {
        try {
            & $runner -ScriptPath $sqlPath `
                      -ServerInstance $ServerInstance `
                      -Database 'master' `
                      -OutputFormat 'Csv' `
                      -OutputPath $csvPath *>$null
        }
        catch {
            $status = 'FAILED'
            $note   = $_.Exception.Message -replace "`r?`n", ' '
        }
    }

    $color = switch ($status) { 'OK' { 'Green' } 'SKIPPED' { 'Yellow' } default { 'Red' } }
    Write-Host ("  [{0,-8}] {1}" -f $status, $s.Label) -ForegroundColor $color

    $summary.Add([PSCustomObject]@{
        Script  = $s.Label
        Status  = $status
        CsvFile = if ($status -eq 'OK') { Split-Path -Leaf $csvPath } else { '' }
        Note    = $note
    })
}

Write-Host ''
Write-Host '--------------------------------------------'
$ok = @($summary | Where-Object Status -eq 'OK').Count
Write-Host "  Captured: $ok scripts" -ForegroundColor Cyan
Write-Host ''
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host "  Output : $outFolder" -ForegroundColor Green
Write-Host ''
if ($Label -eq 'pre') {
    Write-Host '  This is your pre-migration baseline.' -ForegroundColor DarkGray
    Write-Host '  After cutover, run again with -Label post against the target server.' -ForegroundColor DarkGray
    Write-Host '  Compare matching CSVs to validate no configuration or performance regressions.' -ForegroundColor DarkGray
}
else {
    Write-Host '  Compare these CSV files against the pre-migration baseline.' -ForegroundColor DarkGray
    Write-Host '  Key files to compare: server-info, instance-config, wait-stats, io-usage.' -ForegroundColor DarkGray
}
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''
$env:DBASCRIPTS_BATCH = $null
