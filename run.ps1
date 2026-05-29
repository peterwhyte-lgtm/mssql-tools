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

if ($List -or -not $ScriptName) {
    Write-Host ''
    Write-Host 'DBA Scripts — available scripts' -ForegroundColor Cyan
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''

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

    Write-Host 'Usage:' -ForegroundColor Cyan
    Write-Host '  .\run.ps1 <ScriptName> [-ServerInstance .] [-OutputFormat Csv]'
    Write-Host '  .\run.ps1 -List'
    Write-Host ''
    return
}

$launcher = Join-Path $repoRoot 'helpers\Run-Helper.ps1'

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Launcher not found: $launcher"
}

& $launcher -ScriptName $ScriptName @Arguments
