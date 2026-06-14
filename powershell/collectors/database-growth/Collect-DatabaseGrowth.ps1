<#
.SYNOPSIS
Scheduled database growth collector — point-in-time file size snapshots.

.DESCRIPTION
Captures current size, space to limit, autogrowth settings, and growth risk flag
for every online database file. Unlike IO/wait collectors this is point-in-time
(not cumulative) — each snapshot is independently meaningful.

Recommended interval: every 1–6 hours depending on how quickly databases grow.

Output: output-files\collectors\database-growth\<server>-<YYYYMMDD>.csv

.EXAMPLE
.\collectors\database-growth\Collect-DatabaseGrowth.ps1
.\collectors\database-growth\Collect-DatabaseGrowth.ps1 -ServerInstance PROD01\SQL2019
#>
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $PSScriptRoot 'database-growth.sql'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\collectors\database-growth' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$safeName = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
$today    = Get-Date -Format 'yyyyMMdd'
$csvPath  = Join-Path $OutputRoot "$safeName-$today.csv"
$logPath  = Join-Path $OutputRoot "$safeName-collector.log"
$ts       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Write-DbaLog { param([string]$Msg, [string]$L='INFO')
    $line = "[$ts] [$L] $Msg"
    Add-Content -Path $logPath -Value $line -EA SilentlyContinue
    if ($Host.Name -ne 'Default Host') { Write-Host $line }
}

Write-DbaLog "Starting database-growth collection — $ServerInstance"

$rows = $null
$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $p = @{ ServerInstance=$ServerInstance; Database=$Database; InputFile=$sqlScript
            QueryTimeout=30; TrustServerCertificate=$true; ErrorAction='Stop' }
    if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }
    try   { $rows = @(Invoke-Sqlcmd @p) }
    catch { Write-DbaLog "Invoke-Sqlcmd failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -EA SilentlyContinue
    if (-not $sqlcmdExe) { Write-DbaLog 'No SQL tool available.' 'ERROR'; exit 1 }
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "dbg-$(Get-Date -Format 'yyyyMMddHHmmss').tmp.csv")
    $a = @('-S',$ServerInstance,'-d',$Database,'-i',$sqlScript,'-b','-r','1','-t','30','-C','-o',$tmp,'-W','-w','4000','-s',',')
    if ($Username -and $Password) { $a += @('-U',$Username,'-P',$Password) } else { $a += '-E' }
    try {
        & $sqlcmdExe.Source @a
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe exit $LASTEXITCODE" }
        if (Test-Path $tmp) {
            $raw  = @(Import-Csv -LiteralPath $tmp -EA Stop)
            $rows = @($raw | Where-Object { $r=$_; -not ($r.PSObject.Properties.Name | Where-Object { $r.$_ -match '^-+$' }) })
        }
    } catch { Write-DbaLog "sqlcmd.exe failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -EA SilentlyContinue } }
}

if (-not $rows -or $rows.Count -eq 0) {
    Write-DbaLog 'No rows returned.' 'WARN'; exit 0
}

# Alert in log if any files are AT_LIMIT or NEAR_LIMIT
$atLimit   = @($rows | Where-Object { $_.growth_status -eq 'AT_LIMIT' })
$nearLimit = @($rows | Where-Object { $_.growth_status -eq 'NEAR_LIMIT' })
if ($atLimit.Count -gt 0) {
    Write-DbaLog "AT_LIMIT: $(($atLimit | ForEach-Object {"$($_.database_name)/$($_.logical_name)"}) -join ', ')" 'ERROR'
}
if ($nearLimit.Count -gt 0) {
    Write-DbaLog "NEAR_LIMIT: $(($nearLimit | ForEach-Object {"$($_.database_name)/$($_.logical_name)"}) -join ', ')" 'WARN'
}

$fileExists = Test-Path $csvPath
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
$verb = if ($fileExists) { 'appended' } else { 'created' }
Write-DbaLog "OK — $($rows.Count) file(s) $verb to $([IO.Path]::GetFileName($csvPath))"