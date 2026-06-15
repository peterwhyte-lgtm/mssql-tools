<#
.SYNOPSIS
Install or update SQL Server Management Studio (SSMS).

.DESCRIPTION
Detects the currently installed SSMS version, then installs or upgrades via winget
(preferred) or by downloading the installer directly from Microsoft.

SSMS version notes:
  SSMS 17–20 — traditional WiX installer (SSMS-Setup-ENU.exe)
    Silent flags : /install /quiet /norestart
    winget ID    : Microsoft.SQLServerManagementStudio  (resolves to SSMS 20)
    Download URL : https://aka.ms/ssmsfullsetup

  SSMS 22+ — Visual Studio Installer bootstrapper (vs_SSMS.exe)
    Silent flags : --quiet --norestart --wait
    winget       : not in the winget catalog — use -Method download
    Download URL : https://aka.ms/ssms/22/release/vs_SSMS.exe  (default)
    Ref          : https://learn.microsoft.com/en-us/ssms/install/install

  Cannot upgrade SSMS 17-20 in-place to SSMS 22 — the installer framework changed.
  Run uninstall-ssms.ps1 first, then re-run this script.

.PARAMETER Method
Install method: 'download' (default) or 'winget'.
'download' installs SSMS 22 via direct download (default).
'winget' installs SSMS 20 — use only if you specifically need the legacy version.

.PARAMETER Url
Override the download URL. Default targets SSMS 22 (aka.ms/ssms/22/release/vs_SSMS.exe).
Supply a different URL for a specific version or for SSMS 20.

.PARAMETER Passive
Show the VS Installer progress window during install instead of running fully silent.
Use when you want visual feedback beyond the console elapsed-time counter.

.PARAMETER DownloadDir
Folder to save the installer when using -Method download.
Default: output-files\patches\ssms\ under the repo root.

.PARAMETER UsePreview
Use the SSMS Preview winget package (Microsoft.SQLServerManagementStudio.Preview)
instead of the stable one. Only applies to -Method winget.

.PARAMETER WhatIf
Show what would run without executing.

.EXAMPLE
# Install SSMS 22 (default)
.\powershell\patching\ssms\install-ssms.ps1

# Install with VS Installer progress window visible
.\powershell\patching\ssms\install-ssms.ps1 -Passive

# Install SSMS 20 via winget
.\powershell\patching\ssms\install-ssms.ps1 -Method winget

# Check what would run, no changes
.\powershell\patching\ssms\install-ssms.ps1 -WhatIf
#>
param(
    [ValidateSet('winget', 'download')]
    [string]$Method      = 'download',

    [string]$Url,

    [string]$DownloadDir,

    [switch]$UsePreview,

    [switch]$Passive,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ── Admin check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $WhatIf) {
    Write-Host 'ERROR: This script must be run as Administrator (or use -WhatIf to preview without installing).' -ForegroundColor Red; exit 1
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
$logFile  = Join-Path $logDir "ssms-install-$ts.log"

function Write-DbaLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

Write-DbaLog "SSMS install log — $ts" 'Cyan'

# ── Detect current SSMS version ───────────────────────────────────────────────
function Get-InstalledSsms {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($p in $paths) {
        $found = Get-ItemProperty $p -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' } |
            Select-Object -First 1
        if ($found) { return $found }
    }
    return $null
}

$current = Get-InstalledSsms
if ($current) {
    $currentMajor = [int]($current.DisplayVersion -split '\.')[0]
    Write-DbaLog "Installed : $($current.DisplayName)  v$($current.DisplayVersion)" 'White'
    if ($currentMajor -ge 22) {
        Write-DbaLog "           (SSMS 22+ — VS Installer framework)" 'DarkGray'
    }
}
else {
    Write-DbaLog 'SSMS not detected — will perform a fresh install.' 'Yellow'
    $currentMajor = 0
}

# ── winget method ─────────────────────────────────────────────────────────────
if ($Method -eq 'winget') {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-DbaLog 'winget not available — switching to download method.' 'Yellow'
        $Method = 'download'
    }
    else {
        $packageId = if ($UsePreview) {
            'Microsoft.SQLServerManagementStudio.Preview'
        } else {
            'Microsoft.SQLServerManagementStudio'
        }

        # Note: winget 'Microsoft.SQLServerManagementStudio' resolves to SSMS 20 (legacy stable).
        # SSMS 22 is not in the winget source catalog — use -Method download for SSMS 22.

        # Use 'install' for fresh installs, 'upgrade' when already present
        $wingetVerb = if ($current) { 'upgrade' } else { 'install' }

        Write-DbaLog "Method    : winget $wingetVerb  ($packageId)" 'Cyan'

        if ($WhatIf) {
            Write-DbaLog "WhatIf: winget $wingetVerb --id $packageId --silent --accept-source-agreements" 'Yellow'
            return
        }

        Write-DbaLog "Running: winget $wingetVerb --id $packageId ..." 'Cyan'
        $wingetArgs = @(
            $wingetVerb,
            '--id', $packageId,
            '--silent',
            '--accept-source-agreements'
        )
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs `
                    -Wait -PassThru -NoNewWindow

        switch ($proc.ExitCode) {
            0            { Write-DbaLog "winget $wingetVerb completed." 'Green' }
            -1978335212  {
                # No package found in winget source
                if ($current) {
                    Write-DbaLog 'winget could not find a newer package. If running SSMS 22+, use -Method download for VS Installer updates.' 'Yellow'
                } else {
                    Write-DbaLog 'winget could not find the package. Use -Method download to install SSMS 22.' 'Yellow'
                }
            }
            -1978335189  {
                # Package found but no newer version in winget catalog
                if ($currentMajor -ge 22) {
                    Write-DbaLog 'SSMS 22+ is not updated via winget. Use -Method download for in-place VS Installer updates.' 'Yellow'
                } else {
                    Write-DbaLog 'SSMS is at the latest version available in the winget catalog.' 'Green'
                }
            }
            default      { Write-DbaLog "winget exited with code $($proc.ExitCode) — check output above." 'Yellow' }
        }
    }
}

# ── Download method ───────────────────────────────────────────────────────────
if ($Method -eq 'download') {
    # SSMS 22+ (VS Installer bootstrapper):
    #   URL  : https://aka.ms/ssms/22/release/vs_SSMS.exe  (always latest SSMS 22.x)
    #   Flags: --quiet --norestart --wait
    #   Ref  : https://learn.microsoft.com/en-us/ssms/install/install
    #
    # SSMS 20 and below (legacy WiX installer):
    #   URL  : https://aka.ms/ssmsfullsetup  (resolves to latest SSMS 20.x)
    #   Flags: /install /quiet /norestart
    $downloadUrl = if ($Url) { $Url } else { 'https://aka.ms/ssms/22/release/vs_SSMS.exe' }

    $saveDir = if ($DownloadDir) { $DownloadDir } else { $logDir }
    New-Item -ItemType Directory -Path $saveDir -Force | Out-Null

    # Preserve the original filename so installer type can be detected from it
    $installerFileName = Split-Path $downloadUrl -Leaf
    if ($installerFileName -notmatch '\.exe$') { $installerFileName = "SSMS-Setup-$ts.exe" }
    $installerPath = Join-Path $saveDir $installerFileName

    # Detect installer type by filename:
    # vs_SSMS.exe = VS Installer bootstrapper (SSMS 22+) → uses -- style flags
    # SSMS-Setup-ENU.exe = legacy WiX installer (SSMS 20 and below) → uses / style flags
    $isVsBootstrapper = $installerFileName -like 'vs_*.exe'

    Write-DbaLog "Method    : download" 'Cyan'
    Write-DbaLog "URL       : $downloadUrl"
    Write-DbaLog "Installer : $installerFileName ($( if ($isVsBootstrapper) { 'VS bootstrapper — SSMS 22+' } else { 'legacy WiX — SSMS 20 and below' } ))" 'DarkGray'

    # Cross-framework upgrade check:
    # SSMS 20→22 cannot upgrade in-place — the installer framework changed entirely.
    # SSMS 22→22.x can update in-place via the VS bootstrapper.
    if ($current -and $currentMajor -lt 22 -and $isVsBootstrapper) {
        # Covers SSMS 17, 18, 19, 20 — all use the legacy WiX installer framework.
        # SSMS 22+ (VS Installer) cannot upgrade over the top of any of these.
        Write-DbaLog ''
        Write-DbaLog "SSMS $($current.DisplayName) v$($current.DisplayVersion) is installed (legacy WiX installer — versions 17–20)." 'Yellow'
        Write-DbaLog "SSMS 22+ uses the VS Installer framework and cannot upgrade in-place over a legacy SSMS install." 'Yellow'
        Write-DbaLog "Run .\uninstall-ssms.ps1 first, then re-run this script to install SSMS 22." 'Yellow'
        exit 0
    }

    if ($current -and $currentMajor -ge 22 -and $isVsBootstrapper) {
        Write-DbaLog "SSMS $($current.DisplayVersion) detected (VS Installer framework) — bootstrapper will perform an in-place update." 'DarkGray'
    }

    if ($WhatIf) {
        $flags = if ($isVsBootstrapper) { '--quiet --norestart --wait' } else { '/install /quiet /norestart' }
        Write-DbaLog "WhatIf: download '$downloadUrl' → '$installerPath'" 'Yellow'
        Write-DbaLog "WhatIf: Start-Process '$installerPath' $flags" 'Yellow'
        return
    }

    Write-DbaLog 'Downloading SSMS installer...' 'Cyan'
    try {
        Start-BitsTransfer -Source $downloadUrl -Destination $installerPath -DisplayName "SSMS: $installerFileName"
        $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
        Write-DbaLog "Downloaded : $installerFileName ($sizeMB MB)" 'Green'
    }
    catch {
        Write-DbaLog "ERROR: Download failed — $($_.Exception.Message)" 'Red'
        exit 1
    }

    $installArgs = if ($isVsBootstrapper) {
        $uiFlag = if ($Passive) { '--passive' } else { '--quiet' }
        # --wait is required for the bootstrapper: vs_SSMS.exe launches the real VS Installer
        # as a child process and exits immediately without it. --wait holds it open until done.
        @($uiFlag, '--norestart', '--wait')
    } else {
        @('/install', '/quiet', '/norestart')
    }

    Write-DbaLog "Installing SSMS ($($installArgs -join ' '))..." 'Cyan'
    $proc = Start-Process -FilePath $installerPath -ArgumentList $installArgs -PassThru `
        -RedirectStandardOutput "$logFile.vs-stdout.txt" `
        -RedirectStandardError  "$logFile.vs-stderr.txt"
    $sw   = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited) {
        Write-Host ("`r    ... {0:mm\:ss} elapsed" -f $sw.Elapsed) -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }
    Write-Host ''

    switch ($proc.ExitCode) {
        0    { Write-DbaLog 'SSMS install completed.' 'Green' }
        3010 { Write-DbaLog 'SSMS install completed — reboot required.' 'Yellow' }
        default { Write-DbaLog "Installer exited with code $($proc.ExitCode) — verify manually." 'Yellow' }
    }
}

# ── Verify new version ────────────────────────────────────────────────────────
Write-DbaLog ''
Write-DbaLog 'Checking installed SSMS version...' 'Cyan'
$updated = Get-InstalledSsms
if ($updated) {
    if ($current -and $updated.DisplayVersion -ne $current.DisplayVersion) {
        Write-DbaLog "SSMS updated : v$($current.DisplayVersion)  →  v$($updated.DisplayVersion)" 'Green'
    }
    else {
        Write-DbaLog "SSMS version : v$($updated.DisplayVersion)" 'Green'
    }
}
else {
    Write-DbaLog 'Could not read SSMS version from registry — verify manually.' 'Yellow'
}

# ── Add SSMS to PATH ──────────────────────────────────────────────────────────
$ssmsExe = $null

# SSMS 22+: use vswhere to get the install path
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    try {
        $vsProducts = & $vswhere -all -products '*' -format json 2>&1 | ConvertFrom-Json
        $ssmsProduct = $vsProducts |
            Where-Object { $_.displayName -like '*SQL Server Management Studio*' } |
            Select-Object -First 1
        if ($ssmsProduct) {
            $candidate = Join-Path $ssmsProduct.installationPath 'Common7\IDE\Ssms.exe'
            if (Test-Path $candidate) { $ssmsExe = $candidate }
        }
    } catch { }
}

# Legacy SSMS (17-20): try registry InstallLocation then known default paths
if (-not $ssmsExe -and $updated -and $updated.InstallLocation) {
    $candidate = Join-Path $updated.InstallLocation 'Common7\IDE\Ssms.exe'
    if (Test-Path $candidate) { $ssmsExe = $candidate }
}
if (-not $ssmsExe) {
    $knownPaths = @(
        'C:\Program Files\Microsoft SQL Server Management Studio 22\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe',
        'C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe'
    )
    $ssmsExe = $knownPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($ssmsExe) {
    $ssmsDir     = Split-Path $ssmsExe
    $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if ($machinePath -notlike "*$ssmsDir*") {
        [System.Environment]::SetEnvironmentVariable('PATH', "$machinePath;$ssmsDir", 'Machine')
        $env:PATH += ";$ssmsDir"
        Write-DbaLog "PATH updated  : added $ssmsDir" 'Green'
        Write-DbaLog "              Type 'ssms' to launch (current terminal already updated)." 'DarkGray'
    }
    else {
        Write-DbaLog "PATH          : 'ssms' command already available." 'DarkGray'
    }
}

Write-DbaLog ''
Write-DbaLog 'Done.' 'Green'
Write-DbaLog "Log: $logFile"
