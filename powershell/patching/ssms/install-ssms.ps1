<#
.SYNOPSIS
Install or update SQL Server Management Studio (SSMS).

.DESCRIPTION
Detects the currently installed SSMS version, then installs or upgrades via winget
(preferred) or by downloading the installer directly from Microsoft.

SSMS version notes:
  SSMS 20 and below — traditional WiX installer
    Silent flags : /install /quiet /norestart
    winget ID    : Microsoft.SQLServerManagementStudio
    Download URL : https://aka.ms/ssmsfullsetup  (resolves to latest stable)

  SSMS 21 and above — new installer framework (changed with SSMS 21 release)
    Silent flags : /install /quiet /norestart  (verify against your installer)
    winget ID    : Microsoft.SQLServerManagementStudio  (stable GA release)
                   Microsoft.SQLServerManagementStudio.Preview  (preview builds)
    Download URL : supply via -Url parameter (SSMS 21+ has a dedicated URL)

  If you are unsure which version the installer will deliver, run with -WhatIf first,
  then verify the version that was installed afterwards with patch-summary.ps1.

.PARAMETER Method
Install method: 'winget' (default) or 'download'.

.PARAMETER Url
Override the download URL. Required when targeting SSMS 21+ via the download method,
since aka.ms/ssmsfullsetup may still point to the latest SSMS 20 release.
Get the URL from: https://learn.microsoft.com/en-us/ssms/release-notes-ssms

.PARAMETER DownloadDir
Folder to save the installer when using -Method download.
Default: output-files\patches\ssms\ under the repo root.

.PARAMETER UsePreview
Use the SSMS Preview winget package (Microsoft.SQLServerManagementStudio.Preview)
instead of the stable one. Only applies to -Method winget.

.PARAMETER WhatIf
Show what would run without executing.

.EXAMPLE
# Install/update via winget (default, latest stable)
.\powershell\patching\ssms\install-ssms.ps1

# Install SSMS 21 via direct download
.\powershell\patching\ssms\install-ssms.ps1 -Method download -Url 'https://...'

# Install SSMS Preview via winget
.\powershell\patching\ssms\install-ssms.ps1 -UsePreview

# Check what would run, no changes
.\powershell\patching\ssms\install-ssms.ps1 -WhatIf
#>
param(
    [ValidateSet('winget', 'download')]
    [string]$Method      = 'winget',

    [string]$Url,

    [string]$DownloadDir,

    [switch]$UsePreview,

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
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$logDir   = Join-Path $repoRoot 'output-files\patches\ssms'
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
    if ($currentMajor -ge 21) {
        Write-DbaLog "           (SSMS 21+ install detected — verify installer switches if using download method)" 'DarkGray'
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

        Write-DbaLog "Method    : winget  ($packageId)" 'Cyan'

        if ($WhatIf) {
            Write-DbaLog "WhatIf: winget upgrade --id $packageId --silent --accept-source-agreements --accept-package-agreements" 'Yellow'
            return
        }

        Write-DbaLog "Running: winget upgrade --id $packageId ..." 'Cyan'
        $wingetArgs = @(
            'upgrade',
            '--id', $packageId,
            '--silent',
            '--accept-source-agreements',
            '--accept-package-agreements'
        )
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs `
                    -Wait -PassThru -NoNewWindow

        switch ($proc.ExitCode) {
            0            { Write-DbaLog 'winget upgrade completed.' 'Green' }
            -1978335212  { Write-DbaLog 'SSMS is already up to date (winget: no upgrade available).' 'Green' }
            default      { Write-DbaLog "winget exited with code $($proc.ExitCode) — check output above." 'Yellow' }
        }
    }
}

# ── Download method ───────────────────────────────────────────────────────────
if ($Method -eq 'download') {
    # Default URL resolves to latest stable SSMS release.
    # For SSMS 21+, supply a specific URL via -Url parameter.
    # SSMS 21 download links: https://learn.microsoft.com/en-us/ssms/release-notes-ssms
    $downloadUrl = if ($Url) { $Url } else { 'https://aka.ms/ssmsfullsetup' }

    $saveDir = if ($DownloadDir) { $DownloadDir } else { $logDir }
    New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
    $installerPath = Join-Path $saveDir "SSMS-Setup-$ts.exe"

    Write-DbaLog "Method    : download" 'Cyan'
    Write-DbaLog "URL       : $downloadUrl"

    if ($WhatIf) {
        Write-DbaLog "WhatIf: Invoke-WebRequest '$downloadUrl' -> '$installerPath'" 'Yellow'
        Write-DbaLog "WhatIf: Start-Process '$installerPath' /install /quiet /norestart" 'Yellow'
        Write-DbaLog "Note: if downloading SSMS 21+, verify /install /quiet /norestart are still the correct flags." 'DarkGray'
        return
    }

    Write-DbaLog 'Downloading SSMS installer...' 'Cyan'
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -MaximumRedirection 10
        $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
        Write-DbaLog "Downloaded : $installerPath ($sizeMB MB)" 'Green'
    }
    catch {
        Write-DbaLog "ERROR: Download failed — $($_.Exception.Message)" 'Red'
        exit 1
    }

    # Detect SSMS 21+ from the installer version resource if possible
    $installerVersion = (Get-Item $installerPath).VersionInfo.ProductMajorPart
    $isNewInstaller   = $installerVersion -ge 21

    # SSMS 21+ changed the installer framework. Silent flags are believed to be the same
    # but verify against the specific release notes if you encounter install issues.
    $installArgs = @('/install', '/quiet', '/norestart')
    if ($isNewInstaller) {
        Write-DbaLog "Detected SSMS $installerVersion installer (21+ path)." 'Cyan'
        Write-DbaLog "Using flags: $($installArgs -join ' ')  — update if your SSMS 21 release requires different flags." 'DarkGray'
    }
    else {
        Write-DbaLog "Detected SSMS $installerVersion installer (legacy path)." 'Cyan'
    }

    Write-DbaLog 'Installing SSMS...' 'Cyan'
    $proc = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru

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

Write-DbaLog ''
Write-DbaLog 'Done.' 'Green'
Write-DbaLog "Log: $logFile"
