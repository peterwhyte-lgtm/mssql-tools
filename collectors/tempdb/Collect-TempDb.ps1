<#
.SYNOPSIS
Scheduled TempDB collector — appends file-level and session-level TempDB snapshots.

.DESCRIPTION
Captures TempDB file space usage (version store, internal objects, user objects, free)
and the top 10 TempDB-consuming sessions. Appends to a rolling daily CSV.

Output: output-files\collectors\tempdb\<server>-<YYYYMMDD>.csv

.EXAMPLE
.\collectors\tempdb\Collect-TempDb.ps1
.\collectors\tempdb\Collect-TempDb.ps1 -ServerInstance PROD01\SQL2019
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
$sqlScript = Join-Path $PSScriptRoot 'tempdb.sql'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\collectors\tempdb' }
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

Write-DbaLog "Starting TempDB collection — $ServerInstance"

$rows = $null
$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $p = @{ ServerInstance=$ServerInstance; Database=$Database; InputFile=$sqlScript
            QueryTimeout=15; TrustServerCertificate=$true; ErrorAction='Stop' }
    if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }
    try   { $rows = @(Invoke-Sqlcmd @p) }
    catch { Write-DbaLog "Invoke-Sqlcmd failed: $($_.Exception.Message)" 'ERROR'; exit 1 }
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -EA SilentlyContinue
    if (-not $sqlcmdExe) { Write-DbaLog 'No SQL tool available.' 'ERROR'; exit 1 }
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "tdb-$(Get-Date -Format 'yyyyMMddHHmmss').tmp.csv")
    $a = @('-S',$ServerInstance,'-d',$Database,'-i',$sqlScript,'-b','-r','1','-t','15','-C','-o',$tmp,'-W','-w','4000','-s',',')
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

$fileExists = Test-Path $csvPath
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
$verb = if ($fileExists) { 'appended' } else { 'created' }
Write-DbaLog "OK — $($rows.Count) row(s) $verb to $([IO.Path]::GetFileName($csvPath))"
