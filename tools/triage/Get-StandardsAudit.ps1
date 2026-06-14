<#
.SYNOPSIS
    Audits SQL scripts in sql/ for compliance with repo standards.

.DESCRIPTION
    Checks every .sql file under sql/ for:
      PASS/FAIL: block comment header present
      PASS/FAIL: required header fields (Script Name, Category, Purpose, Author, Safe, Impact)
      PASS/FAIL: SET NOCOUNT ON
      PASS/FAIL: -- SAFE: annotation
      PASS/FAIL: -- IMPACT: annotation
      WARN: WITH (NOLOCK) usage
      WARN: deprecated catalog views (sys.sysprocesses, sys.sysobjects, etc.)
      WARN: USE <database> statement (not supported by Invoke-RepoSql)
      WARN: GO batch separator (not supported by Invoke-Sqlcmd)

    Useful for tracking Phase 2 compliance and finding scripts that still need work.

.PARAMETER Category
    Filter to a single category folder (monitoring, performance, backups, security, migration).

.PARAMETER FailsOnly
    Show only scripts with at least one FAIL or WARN.

.PARAMETER OutputFormat
    Table (default) or Csv (saves to output-files\reviews\standards-audit-<timestamp>.csv).

.EXAMPLE
    .\tools\triage\Get-StandardsAudit.ps1
    .\tools\triage\Get-StandardsAudit.ps1 -Category performance -FailsOnly
    .\tools\triage\Get-StandardsAudit.ps1 -OutputFormat Csv

.NOTES
    Type        : runner
    Scope       : local
    RiskLevel   : SAFE
#>
[CmdletBinding()]
param(
    [string]$Category,
    [switch]$FailsOnly,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = 'Stop'
$repoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlRoot     = Join-Path $repoRoot 'sql'
$migrationRoot = Join-Path $repoRoot 'sql\migration'

# Required header fields
$requiredFields = @('Script Name', 'Category', 'Purpose', 'Author', 'Safe', 'Impact')

# Deprecated compatibility catalog views (SQL Server 2005-era aliases for modern sys.* views).
# Does NOT include msdb tables (sysjobs, sysjobsteps, etc.) — those are correct modern tables.
$deprecatedViews = @(
    'sys\.sysprocesses', 'sys\.sysobjects', 'sys\.syslogins', 'sys\.syscolumns',
    'sys\.sysdatabases', 'sys\.sysindexes', 'sys\.systypes', 'sys\.sysusers',
    'master\.dbo\.sysdatabases'
)
$deprecatedPattern = ($deprecatedViews -join '|')

# ── Collect SQL files ──────────────────────────────────────────────────────────
if ($Category -eq 'migration') {
    $searchPaths = @($migrationRoot)
} elseif ($Category) {
    $searchPaths = @(Join-Path $sqlRoot $Category)
} else {
    $searchPaths = @($sqlRoot, $migrationRoot)
}

foreach ($sp in $searchPaths) {
    if (-not (Test-Path $sp)) { Write-Error "Folder not found: $sp"; exit 1 }
}
$sqlFiles = $searchPaths | ForEach-Object {
    Get-ChildItem -Path $_ -Recurse -Filter '*.sql'
} | Sort-Object FullName

if (-not $sqlFiles) {
    Write-Host "No SQL files found under $searchPath" -ForegroundColor Yellow
    exit 0
}

# ── Audit each file ───────────────────────────────────────────────────────────
$results = foreach ($file in $sqlFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $rel     = $file.FullName.Substring($repoRoot.Path.Length + 1).Replace('\', '/')
    $cat     = if ($rel -match 'sql/migration/') { 'migration' } else { $file.Directory.Name }

    $fails = [System.Collections.Generic.List[string]]::new()
    $warns = [System.Collections.Generic.List[string]]::new()

    # ── FAIL checks ───────────────────────────────────────────────────────────
    $hasBlock = $content -match '(?s)/\*.*?\*/'
    if (-not $hasBlock) {
        $fails.Add('no block comment')
    } else {
        foreach ($field in $requiredFields) {
            if ($content -notmatch "(?m)^$field\s*:") {
                $fails.Add("missing: $field")
            }
        }
    }

    if ($content -notmatch '(?m)^SET NOCOUNT ON;') {
        $fails.Add('no SET NOCOUNT ON')
    }
    if ($content -notmatch '(?m)^-- SAFE:') {
        $fails.Add('no -- SAFE: annotation')
    }
    if ($content -notmatch '(?m)^-- IMPACT:') {
        $fails.Add('no -- IMPACT: annotation')
    }

    # ── WARN checks ───────────────────────────────────────────────────────────
    if ($content -imatch '\bWITH\s*\(\s*NOLOCK\s*\)') {
        $warns.Add('WITH (NOLOCK)')
    }
    if ($content -imatch $deprecatedPattern) {
        $matched = [regex]::Matches($content, $deprecatedPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
            ForEach-Object { $_.Value } | Select-Object -Unique
        $warns.Add("deprecated view: $($matched -join ', ')")
    }
    if ($content -imatch '(?m)^\s*USE\s+\w+') {
        $warns.Add('USE <database> (not supported by Invoke-Sqlcmd)')
    }
    if ($content -imatch '(?m)^\s*GO\s*$') {
        $warns.Add('GO separator (not supported by Invoke-Sqlcmd)')
    }

    # ── Status ────────────────────────────────────────────────────────────────
    $status = if ($fails.Count -gt 0) { 'FAIL' } elseif ($warns.Count -gt 0) { 'WARN' } else { 'PASS' }
    $issues = ($fails + $warns) -join ' | '

    [PSCustomObject]@{
        Status   = $status
        Category = $cat
        Script   = $file.BaseName
        Fails    = $fails.Count
        Warns    = $warns.Count
        Issues   = $issues
        Path     = $rel
    }
}

# ── Summary (calculated before filtering) ─────────────────────────────────────
$total   = $sqlFiles.Count
$passing = ($results | Where-Object { $_.Status -eq 'PASS' }).Count
$failing = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$warning = ($results | Where-Object { $_.Status -eq 'WARN' }).Count

# ── Apply filter ──────────────────────────────────────────────────────────────
if ($FailsOnly) {
    $results = $results | Where-Object { $_.Status -ne 'PASS' }
}
$filtered = $results.Count

# ── Output ────────────────────────────────────────────────────────────────────
if ($OutputFormat -eq 'Csv') {
    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outDir  = Join-Path $repoRoot "output-files\reviews\audits"
    $outPath = Join-Path $outDir "standards-audit-$stamp.csv"
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $results | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
    Write-Host "Saved: $outPath" -ForegroundColor Green
} else {
    Write-Host ""
    $scope = if ($Category) { $Category } else { 'all categories' }
    Write-Host "  SQL Standards Audit — $scope" -ForegroundColor Cyan
    if ($Category) { Write-Host "  Category filter: $Category" }
    Write-Host ""

    $display = $results | Select-Object Status, Category, Script, Issues
    $display | Format-Table -AutoSize

    Write-Host "  Summary: $total scripts | PASS: $passing | WARN: $warning | FAIL: $failing"
    if ($FailsOnly -and $filtered -lt $total) {
        Write-Host "  (showing $filtered non-passing scripts)"
    }
    Write-Host ""

    if ($failing -gt 0) {
        Write-Host "  FAIL breakdown:" -ForegroundColor Red
        $results | Where-Object { $_.Status -eq 'FAIL' } |
            ForEach-Object { Write-Host "    $($_.Path): $($_.Issues)" -ForegroundColor Red }
        Write-Host ""
    }
    if ($warning -gt 0) {
        Write-Host "  WARN breakdown:" -ForegroundColor Yellow
        $results | Where-Object { $_.Status -eq 'WARN' } |
            ForEach-Object { Write-Host "    $($_.Path): $($_.Issues)" -ForegroundColor Yellow }
        Write-Host ""
    }
}
