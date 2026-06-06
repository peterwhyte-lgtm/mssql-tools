<#
.SYNOPSIS
Root launcher for DBA helper scripts. Fuzzy name match against powershell/ and sql/.

.DESCRIPTION
Finds and runs any script in the repo by name (partial match accepted).
Use -List to browse all available scripts grouped by category.

.EXAMPLES
  .\run.ps1 Get-WaitStatistics
  .\run.ps1 Get-WaitStatistics -ServerInstance MYSERVER\INST01 -OutputFormat Csv
  .\run.ps1 -List
#>

param(
    [string]$ScriptName,

    [switch]$List,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$repoRoot = Resolve-Path $PSScriptRoot

& (Join-Path $repoRoot 'helpers\local-sql\Install-Prerequisites.ps1')

if ($List -or -not $ScriptName) {
    Write-Host ''
    Write-Host 'DBA Scripts — available scripts' -ForegroundColor Cyan
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''

    # ── Top scripts for production DBA ────────────────────────────────────────
    Write-Host '  Start here' -ForegroundColor Green
    Write-Host ''
    $topScripts = @(
        [PSCustomObject]@{ Name = 'Get-WaitStatistics';             Desc = 'Ranked wait types — first stop for any unexplained slowness' }
        [PSCustomObject]@{ Name = 'Get-BlockingChains';             Desc = 'Who is blocking whom — head-blocker tree with queries' }
        [PSCustomObject]@{ Name = 'Get-ActiveRequests';             Desc = 'Queries running right now — incident first look' }
        [PSCustomObject]@{ Name = 'Get-TopCpuQueries';              Desc = 'Highest CPU queries from plan cache' }
        [PSCustomObject]@{ Name = 'Get-MissingIndexes';             Desc = 'High-impact missing index recommendations' }
        [PSCustomObject]@{ Name = 'Get-DatabaseSizesAndFreeSpace';  Desc = 'All databases — data and log sizes with free space' }
        [PSCustomObject]@{ Name = 'Get-BackupCoverage';             Desc = 'Backup currency across all databases' }
        [PSCustomObject]@{ Name = 'Get-SqlAgentJobFailureSummary';  Desc = 'Recent job failures and duration outliers' }
        [PSCustomObject]@{ Name = 'Get-IndexFragmentation';         Desc = 'Fragmentation and page counts for all indexes' }
        [PSCustomObject]@{ Name = 'Get-InstanceConfigurationScore'; Desc = 'Best-practice configuration score for this instance' }
    )
    foreach ($s in $topScripts) {
        Write-Host ("  {0,-42}" -f $s.Name) -NoNewline -ForegroundColor White
        Write-Host $s.Desc -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''

    # ── Full script listing by category ───────────────────────────────────────
    $sqlRoot = Join-Path $repoRoot 'sql'
    foreach ($folder in (Get-ChildItem $sqlRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $scripts = Get-ChildItem $folder.FullName -Filter '*.sql' -ErrorAction SilentlyContinue | Sort-Object Name
        if ($scripts.Count -gt 0) {
            Write-Host "  sql/$($folder.Name)/" -ForegroundColor Yellow
            $scripts | ForEach-Object { Write-Host "    $($_.BaseName)" -ForegroundColor DarkGray }
            Write-Host ''
        }
    }

    $psRoot = Join-Path $repoRoot 'powershell'
    foreach ($folder in (Get-ChildItem $psRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $scripts = Get-ChildItem $folder.FullName -Filter '*.ps1' -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^(Get|Invoke|Review|Generate|Backup|Restore)-' } |
                   Sort-Object Name
        if ($scripts.Count -gt 0) {
            Write-Host "  powershell/$($folder.Name)/" -ForegroundColor Yellow
            $scripts | ForEach-Object { Write-Host "    $($_.BaseName)" -ForegroundColor DarkGray }
            Write-Host ''
        }
    }

    $wrRoot = Join-Path $repoRoot 'wrappers'
    foreach ($folder in (Get-ChildItem $wrRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $scripts = Get-ChildItem $folder.FullName -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name
        if ($scripts.Count -gt 0) {
            Write-Host "  wrappers/$($folder.Name)/" -ForegroundColor DarkGray
            $scripts | ForEach-Object { Write-Host "    $($_.BaseName)" -ForegroundColor DarkGray }
            Write-Host ''
        }
    }

    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host 'Run a script:' -ForegroundColor Cyan
    Write-Host '  .\run.ps1 Get-WaitStatistics'
    Write-Host '  Results always saved to output-files/ as CSV.' -ForegroundColor DarkGray
    Write-Host '  Add -OutputFormat Csv to suppress terminal output (CSV only).' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Set your server once per session (then no -ServerInstance needed):' -ForegroundColor Cyan
    Write-Host '  .\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance YOURSERVER'
    Write-Host ''
    Write-Host 'Or pass it per-run:' -ForegroundColor Cyan
    Write-Host '  .\run.ps1 Get-WaitStatistics -ServerInstance YOURSERVER'
    Write-Host ''
    Write-Host 'Browser UI (scripts + CSV viewer):' -ForegroundColor Cyan
    Write-Host '  .\tools\web-ui\Start-WebUi.ps1'
    Write-Host ''
    return
}

# Resolve the script name directly — avoids a second hop through Run-Helper
# which mangles named parameters during array splatting.
$searchRoots = @(
    (Join-Path $repoRoot 'powershell'),
    (Join-Path $repoRoot 'wrappers'),
    (Join-Path $repoRoot 'helpers'),
    (Join-Path $repoRoot 'sql'),
    (Join-Path $repoRoot 'tools')
)

$candidates = @()
foreach ($root in $searchRoots) {
    $candidates += Get-ChildItem -Path $root -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like $ScriptName -or $_.BaseName -like "*$ScriptName*" }
}
# Only fall back to .sql if no .ps1 wrapper found
if ($candidates.Count -eq 0) {
    foreach ($root in $searchRoots) {
        $candidates += Get-ChildItem -Path $root -Recurse -File -Include '*.sql' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like $ScriptName -or $_.BaseName -like "*$ScriptName*" }
    }
}

$unique = $candidates | Sort-Object FullName -Unique

# Prefer exact match over fuzzy — prevents e.g. Get-IndexFragmentation being blocked by
# Get-IndexFragmentationAcrossDatabases when the user typed the full name.
$exact = $unique | Where-Object { $_.BaseName -eq $ScriptName }
if ($exact.Count -eq 1) { $unique = $exact }
if ($unique.Count -eq 0) {
    Write-Host "No script matched '$ScriptName'." -ForegroundColor Yellow
    Write-Host "  Try: .\helpers\triage\Find-UsefulScript.ps1 -Keyword $ScriptName" -ForegroundColor DarkGray
    Write-Host ''
    return
}
if ($unique.Count -gt 1) {
    Write-Host "Multiple matches for '$ScriptName' — be more specific:" -ForegroundColor Yellow
    $unique | ForEach-Object { Write-Host "  $([System.IO.Path]::GetRelativePath($repoRoot, $_.FullName))" -ForegroundColor DarkGray }
    Write-Host ''
    return
}

$target = $unique[0].FullName

# SQL files go through Invoke-RepoSql; PS files are called directly.
if ($target -like '*.sql') {
    $runner = Join-Path $repoRoot 'helpers\local-sql\Invoke-RepoSql.ps1'
    $target = $runner
    $Arguments = @('-ScriptPath', $unique[0].FullName) + $Arguments
}

# Parse remaining string args into a hashtable so named params survive splatting.
$splat = @{}
$i = 0
while ($i -lt $Arguments.Count) {
    if ($Arguments[$i] -match '^-{1,2}(.+)$') {
        $key = $Matches[1]
        if (($i + 1) -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-') {
            $splat[$key] = $Arguments[$i + 1]
            $i += 2
        } else {
            $splat[$key] = $true
            $i++
        }
    } else {
        $i++
    }
}

Write-Host "Running: $([System.IO.Path]::GetRelativePath($repoRoot, $target))" -ForegroundColor Cyan
if ($splat.Count -gt 0) { & $target @splat } else { & $target }
