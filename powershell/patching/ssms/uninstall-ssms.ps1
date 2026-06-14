<#
.SYNOPSIS
Silently uninstall SQL Server Management Studio (SSMS).

.DESCRIPTION
Detects all installed SSMS versions from the registry, reads the uninstall command,
and runs it silently. Handles both SSMS 20 and below (traditional WiX installer)
and SSMS 21+ (new installer framework).

Uninstall approach by version:
  SSMS 20 and below — reads QuietUninstallString or constructs from UninstallString.
    The installer EXE supports: /uninstall /quiet /norestart
  SSMS 21 and above — same approach; verify flags if the uninstall behaves unexpectedly.
    If uninstall fails, retrieve the UninstallString from the registry and run manually.

.PARAMETER WhatIf
Show what would run without uninstalling.

.PARAMETER Force
Skip the confirmation prompt before uninstalling.

.EXAMPLE
# Check what would be uninstalled
.\powershell\patching\ssms\uninstall-ssms.ps1 -WhatIf

# Uninstall with confirmation prompt
.\powershell\patching\ssms\uninstall-ssms.ps1

# Uninstall without prompting
.\powershell\patching\ssms\uninstall-ssms.ps1 -Force
#>
param(
    [switch]$WhatIf,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $WhatIf) {
    Write-Host 'ERROR: This script must be run as Administrator (or use -WhatIf to preview without installing).' -ForegroundColor Red; exit 1
}

# ── Logging ───────────────────────────────────────────────────────────────────
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$logDir   = Join-Path $repoRoot 'output-files\patches\ssms'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile  = Join-Path $logDir "ssms-uninstall-$ts.log"

function Write-DbaLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

Write-DbaLog "SSMS uninstall log — $ts" 'Cyan'

# ── Find all installed SSMS entries ──────────────────────────────────────────
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$ssmsEntries = @(
    foreach ($p in $regPaths) {
        Get-ItemProperty $p -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' }
    }
)

if ($ssmsEntries.Count -eq 0) {
    Write-DbaLog 'No SSMS installation detected. Nothing to uninstall.' 'Yellow'
    exit 0
}

foreach ($entry in $ssmsEntries) {
    $version = $entry.DisplayVersion
    $name    = $entry.DisplayName
    $major   = [int]($version -split '\.')[0]

    Write-DbaLog ''
    Write-DbaLog "Found : $name  v$version" 'White'

    # Prefer QuietUninstallString (pre-built silent command); fall back to UninstallString
    $rawCmd = if ($entry.QuietUninstallString) {
        $entry.QuietUninstallString
    } else {
        $entry.UninstallString
    }

    if (-not $rawCmd) {
        Write-DbaLog "  ERROR: No uninstall command found in registry for '$name'." 'Red'
        Write-DbaLog "  Uninstall manually via Settings → Apps." 'Red'
        continue
    }

    Write-DbaLog "  Registry command : $rawCmd" 'DarkGray'

    # Parse exe and existing args from the registry command
    # Registry format: "C:\path\to\Setup.exe" [optional-args]
    if ($rawCmd -match '^"([^"]+)"(.*)$') {
        $exePath     = $Matches[1]
        $existingArgs = $Matches[2].Trim()
    }
    elseif ($rawCmd -match '^(\S+)(.*)$') {
        $exePath     = $Matches[1]
        $existingArgs = $Matches[2].Trim()
    }
    else {
        Write-DbaLog "  ERROR: Cannot parse uninstall command: $rawCmd" 'Red'
        continue
    }

    if (-not (Test-Path $exePath)) {
        Write-DbaLog "  ERROR: Uninstall EXE not found: $exePath" 'Red'
        Write-DbaLog "  SSMS may already be partially removed. Check Settings → Apps." 'Yellow'
        continue
    }

    # Build silent uninstall args
    # SSMS <=20 and SSMS 21+ both use /uninstall /quiet /norestart.
    # If the registry already provided /uninstall (via QuietUninstallString), don't duplicate it.
    $silentArgs = [System.Collections.Generic.List[string]]::new()
    if ($existingArgs -notmatch '/uninstall') { $silentArgs.Add('/uninstall') }
    if ($existingArgs -notmatch '/quiet')     { $silentArgs.Add('/quiet') }
    if ($existingArgs -notmatch '/norestart') { $silentArgs.Add('/norestart') }

    $finalArgs = ($existingArgs + ' ' + ($silentArgs -join ' ')).Trim()

    if ($major -ge 21) {
        Write-DbaLog "  SSMS 21+ detected. Using: $exePath $finalArgs" 'DarkGray'
        Write-DbaLog "  If this fails, retrieve UninstallString from registry and run manually." 'DarkGray'
    }

    Write-DbaLog "  Uninstall command : `"$exePath`" $finalArgs" 'Cyan'

    if ($WhatIf) {
        Write-DbaLog '  [WhatIf] — no changes made.' 'Yellow'
        continue
    }

    if (-not $Force) {
        $answer = Read-Host "  Uninstall '$name' v$version now? (yes/no)"
        if ($answer -notmatch '^(yes|y)$') {
            Write-DbaLog '  Skipped by user.' 'Yellow'
            continue
        }
    }

    Write-DbaLog "  Uninstalling '$name'..." 'Cyan'
    try {
        $proc = Start-Process -FilePath $exePath -ArgumentList $finalArgs -Wait -PassThru
        switch ($proc.ExitCode) {
            0    { Write-DbaLog "  Uninstall completed." 'Green' }
            3010 { Write-DbaLog "  Uninstall completed — reboot required." 'Yellow' }
            default {
                Write-DbaLog "  Uninstall exited with code $($proc.ExitCode) — verify manually." 'Yellow'
            }
        }
    }
    catch {
        Write-DbaLog "  ERROR during uninstall: $($_.Exception.Message)" 'Red'
    }
}

# ── Confirm removal ───────────────────────────────────────────────────────────
if (-not $WhatIf) {
    Write-DbaLog ''
    Write-DbaLog 'Verifying removal...' 'Cyan'
    $stillInstalled = @(
        foreach ($p in $regPaths) {
            Get-ItemProperty $p -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' }
        }
    )
    if ($stillInstalled.Count -eq 0) {
        Write-DbaLog 'SSMS successfully removed.' 'Green'
    }
    else {
        foreach ($e in $stillInstalled) {
            Write-DbaLog "Still detected: $($e.DisplayName) v$($e.DisplayVersion) — may require a reboot to complete." 'Yellow'
        }
    }
}

Write-DbaLog ''
Write-DbaLog 'Done.' 'Green'
Write-DbaLog "Log: $logFile"
