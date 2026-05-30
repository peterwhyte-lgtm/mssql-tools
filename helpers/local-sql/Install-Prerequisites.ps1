<#
.SYNOPSIS
Checks that the repo's SQL execution dependency is available and offers to install it if not.

.DESCRIPTION
Called automatically by run.ps1 on every invocation. The check itself is instant (Get-Command).
The install prompt only fires when neither Invoke-Sqlcmd nor sqlcmd.exe is found.
Non-interactive sessions (CI, -NonInteractive) skip the prompt silently.
#>

$hasCmdlet = [bool](Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)
$hasCli    = [bool](Get-Command sqlcmd.exe    -ErrorAction SilentlyContinue)

if ($hasCmdlet -or $hasCli) { return }

Write-Host ''
Write-Host '  Prerequisite check' -ForegroundColor Yellow
Write-Host ('  ' + ('─' * 58)) -ForegroundColor DarkYellow
Write-Host '  Neither Invoke-Sqlcmd nor sqlcmd.exe was found.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  This repo requires one of:' -ForegroundColor White
Write-Host '    SqlServer module   Install-Module SqlServer -Scope CurrentUser' -ForegroundColor DarkGray
Write-Host '    sqlcmd.exe         installed with SSMS or SQL Server tools' -ForegroundColor DarkGray
Write-Host ''

# Skip the prompt in CI or any non-interactive session
$isInteractive = [Environment]::UserInteractive -and -not $env:CI
if (-not $isInteractive) {
    Write-Warning 'Skipping install prompt (non-interactive session).'
    return
}

$response = Read-Host '  Install the SqlServer module now? [Y/n]'
if ($response -in '', 'y', 'Y') {
    Write-Host ''
    Write-Host '  Installing SqlServer module from PSGallery...' -ForegroundColor Cyan
    Install-Module SqlServer -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    Write-Host '  Done. Invoke-Sqlcmd is now available.' -ForegroundColor Green
    Write-Host ''
} else {
    Write-Host ''
    Write-Host '  Skipped. Run manually when ready:' -ForegroundColor DarkGray
    Write-Host '    Install-Module SqlServer -Scope CurrentUser' -ForegroundColor DarkGray
    Write-Host ''
}
