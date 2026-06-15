<#
.SYNOPSIS
Silently uninstall SQL Server Management Studio (SSMS).

.DESCRIPTION
Detects all installed SSMS versions from the registry and uninstalls silently.

Uninstall approach by version:
  SSMS 17–20 — traditional WiX installer.
    Reads UninstallString from registry, appends /uninstall /quiet /norestart.

  SSMS 22+ — Visual Studio Installer (vs_SSMS.exe / setup.exe).
    WiX flags do not apply. Uses VS Installer CLI discovered via vswhere.exe,
    with winget as a fallback. Registry is checked after to confirm removal.

.PARAMETER Passive
Show the VS Installer progress window during uninstall instead of running fully silent.

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
    [switch]$Force,
    [switch]$Passive
)

$ErrorActionPreference = 'Stop'

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $WhatIf) {
    Write-Host 'ERROR: This script must be run as Administrator (or use -WhatIf to preview without uninstalling).' -ForegroundColor Red; exit 1
}

# ── Logging ───────────────────────────────────────────────────────────────────
# Falls back to a logs\ folder next to the script when run standalone (not in the repo)
$_repoOutputDir = Join-Path $PSScriptRoot '..\..\..\output-files'
$logDir = [System.IO.Path]::GetFullPath($(if (Test-Path $_repoOutputDir) {
    Join-Path $_repoOutputDir 'patches\ssms'
} else {
    Join-Path $PSScriptRoot 'logs'
}))
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
            Where-Object {
                $_.DisplayName -like '*SQL Server Management Studio*' -and
                # Skip MSI sub-component registrations (Language Pack, base MSI entries).
                # UninstallString starting with 'MsiExec.exe /I{' means it's an install-mode
                # registration — the main bootstrapper already removes these sub-components.
                $_.UninstallString -notmatch '^MsiExec\.exe /I\{'
            }
    }
)

if ($ssmsEntries.Count -eq 0) {
    Write-DbaLog 'No SSMS installation detected. Nothing to uninstall.' 'Yellow'
    exit 0
}

$script:uninstallCompletedCleanly = $false

foreach ($entry in $ssmsEntries) {
    $version = $entry.DisplayVersion
    $name    = $entry.DisplayName
    $major   = [int]($version -split '\.')[0]

    Write-DbaLog ''
    Write-DbaLog "Found : $name  v$version" 'White'

    if ($WhatIf) {
        $method = if ($major -ge 22) { 'VS Installer CLI or winget' } else { 'WiX /uninstall /quiet /norestart' }
        Write-DbaLog "  [WhatIf] Would uninstall '$name' via $method." 'Yellow'
        continue
    }

    if (-not $Force) {
        $answer = Read-Host "  Uninstall '$name' v$version now? (yes/no)"
        if ($answer -notmatch '^(yes|y)$') {
            Write-DbaLog '  Skipped by user.' 'Yellow'
            continue
        }
    }

    # ── Check if SSMS is running ──────────────────────────────────────────────
    $ssmsProc  = Get-Process -Name 'ssms' -ErrorAction SilentlyContinue
    $forceClose = $false
    if ($ssmsProc) {
        $pidList = ($ssmsProc | ForEach-Object { $_.Id }) -join ', '
        Write-DbaLog "  WARNING: SSMS is currently running (PID $pidList)." 'Yellow'
        if ($Force) {
            Write-DbaLog "  -Force specified — will close SSMS automatically." 'Yellow'
            $forceClose = $true
        }
        else {
            $closeAnswer = Read-Host "  Force close SSMS before uninstalling? (yes/no)"
            if ($closeAnswer -notmatch '^(yes|y)$') {
                Write-DbaLog "  Skipped — close SSMS manually and re-run." 'Yellow'
                continue
            }
            $forceClose = $true
        }
    }

    # ── SSMS 22+ (Visual Studio Installer) ───────────────────────────────────
    if ($major -ge 22) {
        Write-DbaLog "  Uninstalling '$name'..." 'Cyan'
        $uninstalled = $false
        $forceFlag   = if ($forceClose) { ' --force' } else { '' }
        $uiFlag      = if ($Passive)    { '--passive' } else { '--quiet' }

        # Try VS Installer CLI via vswhere first (-products * required to find SSMS)
        $vswhere     = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
        $vsInstaller = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'

        if ((Test-Path $vswhere) -and (Test-Path $vsInstaller)) {
            try {
                $vsProducts  = & $vswhere -all -products '*' -format json 2>&1 | ConvertFrom-Json
                $ssmsProduct = $vsProducts |
                    Where-Object { $_.displayName -like '*SQL Server Management Studio*' } |
                    Select-Object -First 1

                if ($ssmsProduct) {
                    $vsArgs = "uninstall --productId $($ssmsProduct.productId) --channelId $($ssmsProduct.channelId) $uiFlag --norestart$forceFlag"
                    $proc   = Start-Process -FilePath $vsInstaller -ArgumentList $vsArgs -PassThru `
                        -RedirectStandardOutput "$logFile.vs-stdout.txt" `
                        -RedirectStandardError  "$logFile.vs-stderr.txt"
                    $sw     = [System.Diagnostics.Stopwatch]::StartNew()
                    while (-not $proc.HasExited) {
                        Write-Host ("`r    ... {0:mm\:ss} elapsed" -f $sw.Elapsed) -NoNewline -ForegroundColor DarkGray
                        Start-Sleep -Seconds 2
                    }
                    Write-Host ''
                    # Trust registry over exit code — VS Installer can return non-standard codes
                    # even on a successful uninstall
                    $stillThere = @(foreach ($p in $regPaths) {
                        Get-ItemProperty $p -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' -and $_.UninstallString -notmatch '^MsiExec\.exe /I\{' }
                    })
                    if ($stillThere.Count -eq 0) {
                        $script:uninstallCompletedCleanly = $true
                        $uninstalled = $true
                    }
                }
            }
            catch { }
        }

        # Winget fallback
        if (-not $uninstalled) {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if ($winget) {
                $wingetAttempts = @(
                    @('uninstall', '--id', 'Microsoft.SQLServerManagementStudio', '-e', '--silent', '--accept-source-agreements'),
                    @('uninstall', '--name', "`"$name`"", '-e', '--silent', '--accept-source-agreements')
                )
                foreach ($wingetArgs in $wingetAttempts) {
                    $proc = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                    if ($proc.ExitCode -in 0, 3010) {
                        $script:uninstallCompletedCleanly = $true
                        $uninstalled = $true
                        break
                    }
                }
            }
        }

        if ($uninstalled) {
            Write-DbaLog '  Uninstall completed.' 'Green'
        } else {
            Write-DbaLog '  Uninstall failed — remove manually via Settings → Apps or: winget uninstall --id Microsoft.SQLServerManagementStudio -e' 'Red'
        }
        continue
    }

    # ── SSMS 20 and below (WiX installer) ────────────────────────────────────
    $rawCmd = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }

    if (-not $rawCmd) {
        Write-DbaLog "  ERROR: No uninstall command in registry for '$name'. Use Settings → Apps." 'Red'
        continue
    }

    if ($rawCmd -match '^"([^"]+)"(.*)$') {
        $exePath      = $Matches[1]
        $existingArgs = $Matches[2].Trim()
    }
    elseif ($rawCmd -match '^(\S+)(.*)$') {
        $exePath      = $Matches[1]
        $existingArgs = $Matches[2].Trim()
    }
    else {
        Write-DbaLog "  ERROR: Cannot parse uninstall command." 'Red'; continue
    }

    if (-not (Test-Path $exePath)) {
        Write-DbaLog "  ERROR: Uninstall EXE not found: $exePath" 'Red'; continue
    }

    $silentArgs = [System.Collections.Generic.List[string]]::new()
    if ($existingArgs -notmatch '/uninstall') { $silentArgs.Add('/uninstall') }
    if ($existingArgs -notmatch '/quiet')     { $silentArgs.Add('/quiet') }
    if ($existingArgs -notmatch '/norestart') { $silentArgs.Add('/norestart') }
    $finalArgs = ($existingArgs + ' ' + ($silentArgs -join ' ')).Trim()

    Write-DbaLog "  Uninstalling '$name'..." 'Cyan'
    try {
        $proc = Start-Process -FilePath $exePath -ArgumentList $finalArgs -PassThru
        $sw   = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited) {
            Write-Host ("`r    ... {0:mm\:ss} elapsed" -f $sw.Elapsed) -NoNewline -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
        }
        Write-Host ''
        switch ($proc.ExitCode) {
            0    { Write-DbaLog '  Uninstall completed.' 'Green' }
            3010 { Write-DbaLog '  Uninstall completed — reboot required.' 'Yellow' }
            default { Write-DbaLog "  Uninstall exited with code $($proc.ExitCode) — verify manually." 'Yellow' }
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
                Where-Object {
                    $_.DisplayName -like '*SQL Server Management Studio*' -and
                    $_.UninstallString -notmatch '^MsiExec\.exe /I\{'
                }
        }
    )
    if ($stillInstalled.Count -eq 0) {
        Write-DbaLog 'SSMS successfully removed.' 'Green'
    }
    else {
        foreach ($e in $stillInstalled) {
            Write-DbaLog "Still detected: $($e.DisplayName) v$($e.DisplayVersion)" 'Yellow'
            if ($script:uninstallCompletedCleanly) {
                Write-DbaLog "  Uninstaller exited cleanly — a reboot is likely required to finish removal." 'Yellow'
            }
            else {
                Write-DbaLog "  The uninstall may have been cancelled." 'Yellow'
                Write-DbaLog "  Re-run this script to try again, or use: Settings → Apps → Uninstall" 'DarkGray'
            }
        }
    }
}

Write-DbaLog ''
Write-DbaLog 'Done.' 'Green'
Write-DbaLog "Log: $logFile"
