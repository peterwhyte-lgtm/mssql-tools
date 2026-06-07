<#
.SYNOPSIS
Finds DBA scripts matching a keyword — searches both file names and script content.

.EXAMPLE
.\helpers\triage\Find-UsefulScript.ps1 -Keyword blocking
.\helpers\triage\Find-UsefulScript.ps1 -Keyword backup
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Keyword
)
$ErrorActionPreference = 'Stop'

$repoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$searchRoots = @('sql', 'powershell', 'helpers', 'hybrid', 'tools')

$found = $searchRoots | ForEach-Object {
    $path = Join-Path $repoRoot $_
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
    }
} | Where-Object {
    $_.Name -match [regex]::Escape($Keyword) -or
    (Select-String -Path $_.FullName -Pattern $Keyword -Quiet -ErrorAction SilentlyContinue)
} | Sort-Object FullName

if (-not $found) {
    Write-Warning "No scripts matched '$Keyword'."
    return
}

Write-Host ""
Write-Host "  Scripts matching '$Keyword':" -ForegroundColor Cyan
Write-Host ("  " + [string]::new('-', 60)) -ForegroundColor DarkCyan

foreach ($file in $found) {
    $rel = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName)
    Write-Host "  $rel" -ForegroundColor Green

    $purposeLine = Get-Content $file.FullName -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*Purpose\s*:' } |
        Select-Object -First 1
    if ($purposeLine) {
        $purposeText = ($purposeLine -replace '^\s*Purpose\s*:\s*', '').Trim()
        Write-Host "    $purposeText" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  Run any script with:  .\run.ps1 <ScriptName>" -ForegroundColor DarkGray
Write-Host ""
