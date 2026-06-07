<#
.SYNOPSIS
Sets, shows, or clears the session-level SQL Server connection defaults.

.DESCRIPTION
Stores connection details in environment variables for the current PowerShell session.
All scripts that call Invoke-RepoSql.ps1 will pick these up automatically, so you only
need to set them once per session rather than repeating -ServerInstance on every run.

Env vars used:
  $env:DBASCRIPTS_SERVER  — target SQL Server instance
  $env:DBASCRIPTS_USER    — SQL login username (empty = Windows auth)
  $env:DBASCRIPTS_PASS    — SQL login password (cleared when session ends)

SECURITY NOTE:
  Windows (integrated) auth is always preferred. It uses Kerberos/NTLM — no password
  is stored anywhere by this script. Use SQL auth only when Windows auth is not possible.

  When SQL auth is used, the password is stored in $env:DBASCRIPTS_PASS as plain text
  for the lifetime of the session. Plain-text env vars are visible to other processes
  running as the same Windows user. The variable is cleared automatically when the
  PowerShell session ends. Never use SQL auth on shared or multi-user machines.

.PARAMETER ServerInstance
SQL Server instance to target. Accepts any sqlcmd-style format:
  SERVERNAME, SERVERNAME\INSTANCE, SERVERNAME,PORT, 192.168.1.10\INST,1433

.PARAMETER Username
SQL login username. If provided, you will be prompted for the password.
Omit to use Windows (integrated) authentication.

.PARAMETER WindowsAuth
Switch to Windows integrated auth and clear any stored SQL credentials.

.PARAMETER Clear
Reset all connection defaults — back to local (.) with Windows auth.

.PARAMETER Show
Display the current active connection settings.

.EXAMPLE
# Point all scripts at a remote server with Windows auth
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

.EXAMPLE
# Remote server with SQL auth (prompts for password)
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa

.EXAMPLE
# Named instance with non-default port
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance "PROD01\INST01,14330"

.EXAMPLE
# See what is currently set
.\helpers\local-sql\Set-SqlConnection.ps1 -Show

.EXAMPLE
# Reset back to local defaults
.\helpers\local-sql\Set-SqlConnection.ps1 -Clear
#>

param(
    [string]$ServerInstance,
    [string]$Username,
    [switch]$WindowsAuth,
    [switch]$Clear,
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

function Show-Connection {
    $server  = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '. (local)' }
    $auth    = if ($env:DBASCRIPTS_USER)   { "SQL auth  ($($env:DBASCRIPTS_USER))" } else { 'Windows auth (integrated)' }
    Write-Host ''
    Write-Host '  Active SQL connection' -ForegroundColor Cyan
    Write-Host "  Server : $server" -ForegroundColor White
    Write-Host "  Auth   : $auth"   -ForegroundColor White
    Write-Host ''
}

if ($Clear) {
    $env:DBASCRIPTS_SERVER = $null
    $env:DBASCRIPTS_USER   = $null
    $env:DBASCRIPTS_PASS   = $null
    Write-Host 'Connection reset — targeting local (.) with Windows auth.' -ForegroundColor Green
    return
}

if ($Show -or (-not $ServerInstance -and -not $Username -and -not $WindowsAuth)) {
    Show-Connection
    return
}

if ($ServerInstance) {
    $env:DBASCRIPTS_SERVER = $ServerInstance
    Write-Host "Server set to: $ServerInstance" -ForegroundColor Green
}

if ($WindowsAuth) {
    $env:DBASCRIPTS_USER = $null
    $env:DBASCRIPTS_PASS = $null
    Write-Host 'Auth set to: Windows (integrated)' -ForegroundColor Green
}
elseif ($Username) {
    $env:DBASCRIPTS_USER = $Username
    $secure = Read-Host "Password for '$Username'" -AsSecureString
    $env:DBASCRIPTS_PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    Write-Host "Auth set to: SQL auth ($Username)" -ForegroundColor Green
    Write-Host "  NOTE: password stored as plain text in session env var — use Windows auth when possible." -ForegroundColor DarkYellow
}

Show-Connection
