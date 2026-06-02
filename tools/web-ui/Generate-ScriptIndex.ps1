<#
.SYNOPSIS
Generates docs/script-index.md from script headers. Re-run after adding scripts.

.EXAMPLE
.\tools\Generate-ScriptIndex.ps1
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$outFile  = Join-Path $repoRoot 'docs\script-index.md'

function Get-SqlPurpose([string]$Path) {
    $line = Get-Content $Path -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*Purpose\s*:' } |
        Select-Object -First 1
    if ($line) { ($line -replace '^\s*Purpose\s*:\s*', '').Trim() } else { '—' }
}

function Get-PsSynopsis([string]$Path) {
    $lines = Get-Content $Path -ErrorAction SilentlyContinue
    $inBlock = $false
    foreach ($line in $lines) {
        if ($line -match '\.SYNOPSIS') { $inBlock = $true; continue }
        if ($inBlock) {
            $text = $line.Trim()
            if ($text -and $text -notmatch '^\.') { return $text }
            if ($text -match '^\.') { break }
        }
    }
    return '—'
}

$sb = [System.Text.StringBuilder]::new()

$null = $sb.AppendLine('# Script Index')
$null = $sb.AppendLine('')
$null = $sb.AppendLine('All scripts with one-line descriptions, organised by layer and category.')
$null = $sb.AppendLine('Re-generate with `.\tools\Generate-ScriptIndex.ps1` after adding scripts.')
$null = $sb.AppendLine('')

# ── SQL scripts ──────────────────────────────────────────────────────────────
$null = $sb.AppendLine('## SQL Scripts')
$null = $sb.AppendLine('')
$null = $sb.AppendLine('Run directly in SSMS / Azure Data Studio, or via `.\run.ps1 <ScriptName>`.')
$null = $sb.AppendLine('')

$sqlDirs = Get-ChildItem -Path (Join-Path $repoRoot 'sql') -Directory |
    Where-Object { $_.Name -ne 'lab' } |
    Sort-Object Name

foreach ($dir in $sqlDirs) {
    $files = Get-ChildItem -Path $dir.FullName -File -Filter '*.sql' | Sort-Object Name
    if (-not $files) { continue }

    $null = $sb.AppendLine("### $($dir.Name)  ($($files.Count) scripts)")
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| Script | Purpose |')
    $null = $sb.AppendLine('|--------|---------|')

    foreach ($file in $files) {
        $purpose = Get-SqlPurpose $file.FullName
        $null = $sb.AppendLine("| ``$($file.BaseName)`` | $purpose |")
    }
    $null = $sb.AppendLine('')
}

# ── PowerShell scripts ───────────────────────────────────────────────────────
$null = $sb.AppendLine('## PowerShell Scripts')
$null = $sb.AppendLine('')
$null = $sb.AppendLine('Wrappers and orchestrators. Run via `.\run.ps1 <ScriptName>` or directly.')
$null = $sb.AppendLine('')

$psDirs = Get-ChildItem -Path (Join-Path $repoRoot 'powershell') -Directory |
    Where-Object { $_.Name -ne 'lab' } |
    Sort-Object Name

foreach ($dir in $psDirs) {
    $files = Get-ChildItem -Path $dir.FullName -File -Filter '*.ps1' | Sort-Object Name
    if (-not $files) { continue }

    $null = $sb.AppendLine("### $($dir.Name)  ($($files.Count) scripts)")
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| Script | Synopsis |')
    $null = $sb.AppendLine('|--------|---------|')

    foreach ($file in $files) {
        $synopsis = Get-PsSynopsis $file.FullName
        $null = $sb.AppendLine("| ``$($file.BaseName)`` | $synopsis |")
    }
    $null = $sb.AppendLine('')
}

$sb.ToString().TrimEnd() | Set-Content -Path $outFile -Encoding UTF8
$lineCount = (Get-Content $outFile).Count
Write-Host "Written: docs\script-index.md  ($lineCount lines)" -ForegroundColor Green
