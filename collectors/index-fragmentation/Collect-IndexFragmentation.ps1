<#
.SYNOPSIS
Scheduled index fragmentation collector — weekly snapshot across all user databases.

.DESCRIPTION
Iterates all online user databases and captures index fragmentation using SAMPLED
mode (fast, representative). Appends to a weekly CSV. Run off-peak — SAMPLED mode
reads a subset of index pages.

Recommended schedule: weekly, Sunday 2am (or off-peak window).

Output: output-files\collectors\index-fragmentation\<server>-<YYYYMMDD>.csv

.EXAMPLE
.\collectors\index-fragmentation\Collect-IndexFragmentation.ps1
.\collectors\index-fragmentation\Collect-IndexFragmentation.ps1 -ServerInstance PROD01\SQL2019
#>
param(
    [string]$ServerInstance = '.',
    [string]$Username,
    [string]$Password,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $PSScriptRoot 'index-fragmentation.sql'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\collectors\index-fragmentation' }
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

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if (-not $invokeSqlcmd) {
    Write-CollectorLog 'SqlServer module (Invoke-Sqlcmd) required for this collector.' 'ERROR'; exit 1
}

# Enumerate user databases
$dbList = $null
try {
    $p = @{ ServerInstance=$ServerInstance; Database='master'
            Query="SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE'"
            TrustServerCertificate=$true; ErrorAction='Stop' }
    if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }
    $dbList = @(Invoke-Sqlcmd @p)
} catch { Write-CollectorLog "Failed to enumerate databases: $($_.Exception.Message)" 'ERROR'; exit 1 }

if (-not $dbList -or $dbList.Count -eq 0) {
    Write-CollectorLog 'No user databases found.'; exit 0
}

Write-CollectorLog "Starting index fragmentation collection — $($dbList.Count) database(s)"

$totalRows = 0
foreach ($db in $dbList) {
    $dbName = $db.name
    try {
        $p = @{ ServerInstance=$ServerInstance; Database=$dbName; InputFile=$sqlScript
                QueryTimeout=600; TrustServerCertificate=$true; ErrorAction='Stop' }
        if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }

        $rows = @(Invoke-Sqlcmd @p)
        if ($rows -and $rows.Count -gt 0) {
            $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
            $totalRows += $rows.Count
            Write-CollectorLog "  $dbName — $($rows.Count) index(es) captured"
        }
    } catch {
        Write-CollectorLog "  $dbName — FAILED: $($_.Exception.Message)" 'WARN'
    }
}

Write-CollectorLog "OK — $totalRows total rows across $($dbList.Count) database(s)"
