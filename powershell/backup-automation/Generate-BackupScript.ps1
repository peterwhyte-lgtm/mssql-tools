<#
.SYNOPSIS
Generates a full backup T-SQL script for all user databases to review in SSMS.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE

.DESCRIPTION
Bypasses the standard CSV pipeline so Invoke-Sqlcmd uses MaxCharLength 2000000 and
the full NVARCHAR(MAX) result is never truncated. Always writes a .sql file to
output-files\backups\. When called with -OutputPath (web UI mode) also writes a
single-column CSV so the web UI can display and copy the full script.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER if set.

.PARAMETER Database
Initial connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputFormat
Accepted for compatibility with the web UI run path. Has no effect on output format.

.PARAMETER OutputPath
When supplied (web UI mode), writes a single-column CSV to this path so the
web UI can redirect to the result page.

.EXAMPLE
.\powershell\backup-automation\Generate-BackupScript.ps1
.\powershell\backup-automation\Generate-BackupScript.ps1 -ServerInstance PROD01\SQL2019
#>
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [ValidateSet('Table','Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath,
    [switch]$PrintDdl
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $repoRoot 'sql\backups\Generate-BackupScript.sql'
if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

Write-Host '[generate] Generating backup script...' -ForegroundColor Cyan
Write-Host "[generate] Server : $ServerInstance" -ForegroundColor Cyan

$ddlText = $null

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $params = @{
        ServerInstance         = $ServerInstance
        Database               = $Database
        InputFile              = $sqlScript
        QueryTimeout           = 120
        MaxCharLength          = 2000000
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) { $params['Username'] = $Username; $params['Password'] = $Password }
    $result  = Invoke-Sqlcmd @params
    $ddlText = $result.script
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.' }
    $sqlArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $sqlScript, '-y', '0', '-b', '-C')
    if ($Username -and $Password) { $sqlArgs += @('-U', $Username, '-P', $Password) } else { $sqlArgs += '-E' }
    $lines = & $sqlcmdExe.Source @sqlArgs
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe failed with exit code $LASTEXITCODE" }
    # -y 0 outputs raw data with no header/separator rows — join all lines directly
    $ddlText = ($lines -join "`r`n").Trim()
}

if (-not $ddlText -or $ddlText.Trim() -eq '') {
    Write-Host '[generate] No output — no user databases found on this instance.' -ForegroundColor Yellow
    return
}

# Always write a .sql file for direct use in SSMS
$safeName   = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$ts         = Get-Date -Format 'yyyyMMdd-HHmmss'
$sqlOutDir  = Join-Path $repoRoot 'output-files\backups'
New-Item -ItemType Directory -Path $sqlOutDir -Force | Out-Null
$sqlOutPath = Join-Path $sqlOutDir "backup-script-$safeName-$ts.sql"
[System.IO.File]::WriteAllText($sqlOutPath, $ddlText, [System.Text.Encoding]::UTF8)

# Write a single-column CSV when called from the web UI (-OutputPath provided)
# The web UI detects a single 'script' column and renders it as copyable DDL
if ($OutputPath) {
    $csvDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $csvDir)) { New-Item -ItemType Directory -Path $csvDir -Force | Out-Null }
    [PSCustomObject]@{ script = $ddlText } | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
}

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done — $lineCount lines  |  $($ddlText.Length) chars" -ForegroundColor Green
Write-Host "[generate] .sql : $sqlOutPath" -ForegroundColor Green
Write-Host ''
if ($PrintDdl) {
    Write-Host $ddlText
} else {
    Write-Host "  Open the .sql file above in SSMS, or rerun with -PrintDdl to print the DDL here." -ForegroundColor DarkGray
}
