<#
.SYNOPSIS
Clears the repo output-files folder while preserving the folder structure.

.DESCRIPTION
Deletes generated CSV, log, and backup-review content from output-files.
Useful before rerunning the DBA review scripts or before archiving a session.

.PARAMETER Path
Optional output directory to clear. Defaults to .\output-files.

.PARAMETER Mode
Controls the cleanup strategy:
  - all: removes all files and folders under the output root
  - age: removes CSV and markdown output files older than -AgeDays

.PARAMETER AgeDays
Age threshold in days for output file cleanup when -Mode age is used. Defaults to 30.

.PARAMETER WhatIf
Shows what would be removed without deleting anything.
#>

param(
    [string]$Path = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')) 'output-files'),
    [ValidateSet('all', 'age')]
    [string]$Mode = 'all',
    [int]$AgeDays = 30,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

$resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
    $Path
}
else {
    Join-Path $repoRoot $Path
}

if (-not (Test-Path -LiteralPath $resolvedPath)) {
    throw "Output path not found: $resolvedPath"
}

if ($Mode -eq 'age') {
    $cutoff = (Get-Date).AddDays(-$AgeDays)
    $items = Get-ChildItem -LiteralPath $resolvedPath -File -Recurse -Force |
        Where-Object {
            $_.Extension -in '.csv', '.md' -and $_.LastWriteTime -lt $cutoff
        }

    if (-not $items) {
        Write-Host "No output files older than $AgeDays day(s) were found under $resolvedPath" -ForegroundColor Yellow
        return
    }

    if ($WhatIf) {
        $items | Select-Object -ExpandProperty FullName | Write-Host
        Write-Host "Would remove $($items.Count) file(s) older than $AgeDays day(s)." -ForegroundColor Cyan
        return
    }

    $items | Remove-Item -Force -ErrorAction Stop
    Write-Host "Removed $($items.Count) file(s) older than $AgeDays day(s) from $resolvedPath" -ForegroundColor Green
    return
}

$items = Get-ChildItem -LiteralPath $resolvedPath -Force
if (-not $items) {
    Write-Host "No files found under $resolvedPath" -ForegroundColor Yellow
    return
}

if ($WhatIf) {
    $items | Select-Object -ExpandProperty FullName | Write-Host
    Write-Host "Would remove $($items.Count) item(s) from $resolvedPath." -ForegroundColor Cyan
    return
}

$items | Remove-Item -Force -Recurse -ErrorAction Stop
Write-Host "Cleared $($items.Count) item(s) from $resolvedPath" -ForegroundColor Green
