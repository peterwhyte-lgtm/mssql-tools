<#
.SYNOPSIS
Scheduled VLF count collector — appends a daily snapshot to CSV.

.DESCRIPTION
Captures Virtual Log File counts for all online user databases. High VLF counts
slow log backup, recovery, and database startup. Run daily to track growth.

Output: output-files\collectors\vlf-count\<server>-<YYYYMMDD>.csv

.EXAMPLE
.\collectors\vlf-count\Collect-VlfCount.ps1
.\collectors\vlf-count\Collect-VlfCount.ps1 -ServerInstance PROD01\SQL2019
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

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $PSScriptRoot 'vlf-count.sql'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\collectors\vlf-count' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$safeName = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
$today    = Get-Date -Format 'yyyyMMdd'
$csvPath  = Join-Path $OutputRoot "$safeName-$today.csv"
$logPath  = Join-Path $OutputRoot "$safeName-collector.log"
$ts       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Write-CollectorLog { param([string]$Msg, [string]$Level = 'INFO')
    $line = "[$ts] [$Level] $Msg"
    Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    if ($Host.Name -ne 'Default Host') { Write-Host $line }
}

Write-CollectorLog "Starting VLF count collection — server: $ServerInstance"

$rows = $null
$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $p = @{ ServerInstance=$ServerInstance; Database=$Database; InputFile=$sqlScript
            QueryTimeout=60; TrustServerCertificate=$true; ErrorAction='Stop' }
    if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }
    try   { $rows = @(Invoke-Sqlcmd @p) }
    catch { Write-CollectorLog "Invoke-Sqlcmd failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { Write-CollectorLog 'No SQL tool available.' 'ERROR'; exit 1 }
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "vlf-$(Get-Date -Format 'yyyyMMddHHmmss').tmp.csv")
    $a = @('-S',$ServerInstance,'-d',$Database,'-i',$sqlScript,'-b','-r','1','-t','60','-C','-o',$tmp,'-W','-w','4000','-s',',')
    if ($Username -and $Password) { $a += @('-U',$Username,'-P',$Password) } else { $a += '-E' }
    try {
        & $sqlcmdExe.Source @a
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe exit $LASTEXITCODE" }
        if (Test-Path $tmp) {
            $raw  = @(Import-Csv -LiteralPath $tmp -ErrorAction Stop)
            $rows = @($raw | Where-Object { $r=$_; -not ($r.PSObject.Properties.Name | Where-Object { $r.$_ -match '^-+$' }) })
        }
    } catch { Write-CollectorLog "sqlcmd.exe failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }
}

if (-not $rows -or $rows.Count -eq 0) {
    Write-CollectorLog 'No rows returned.' 'WARN'; exit 0
}

$critical = @($rows | Where-Object { $_.vlf_status -eq 'CRITICAL' })
$warning  = @($rows | Where-Object { $_.vlf_status -eq 'WARNING' })

$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8

$msg = "OK — $($rows.Count) database(s) snapshotted"
if ($critical.Count -gt 0) { $msg += " | CRITICAL: $($critical.Count) db(s) >= 10000 VLFs" }
if ($warning.Count  -gt 0) { $msg += " | WARNING: $($warning.Count) db(s) >= 1000 VLFs" }
Write-CollectorLog $msg (if ($critical.Count -gt 0) { 'ERROR' } elseif ($warning.Count -gt 0) { 'WARN' } else { 'INFO' })
