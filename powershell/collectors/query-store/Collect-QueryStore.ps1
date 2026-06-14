<#
.SYNOPSIS
Scheduled Query Store collector — captures top queries from all QS-enabled databases.

.DESCRIPTION
Iterates all user databases with Query Store enabled. For each, captures the top 50
queries by average CPU from the most recently completed runtime stats interval.
Appends only new intervals (deduplicates on interval_start) to avoid duplicate rows.

Output: output-files\collectors\query-store\<server>-<YYYYMMDD>.csv

.EXAMPLE
.\collectors\query-store\Collect-QueryStore.ps1
.\collectors\query-store\Collect-QueryStore.ps1 -ServerInstance PROD01\SQL2019
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

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $PSScriptRoot 'query-store.sql'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\collectors\query-store' }
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

# Find all user databases with Query Store enabled
$dbQuery = "SELECT name FROM sys.databases WHERE is_query_store_on = 1 AND database_id > 4 AND state_desc = 'ONLINE'"
$qsDatabases = $null

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
$sqlcmdExe    = Get-Command sqlcmd.exe    -ErrorAction SilentlyContinue

if (-not $invokeSqlcmd -and -not $sqlcmdExe) {
    Write-CollectorLog 'No SQL tool available.' 'ERROR'; exit 1
}

function Invoke-Sql {
    param([string]$Query, [string]$Db = 'master', [string]$File)
    $p = @{ ServerInstance=$ServerInstance; Database=$Db; TrustServerCertificate=$true
            QueryTimeout=120; ErrorAction='Stop' }
    if ($Username -and $Password) { $p['Username']=$Username; $p['Password']=$Password }
    if ($File)  { $p['InputFile'] = $File }
    else        { $p['Query']     = $Query }
    if ($invokeSqlcmd) { return @(Invoke-Sqlcmd @p) }
    # sqlcmd.exe fallback omitted for brevity — add if needed
}

try   { $qsDatabases = @(Invoke-Sql -Query $dbQuery) }
catch { Write-CollectorLog "Failed to enumerate QS databases: $($_.Exception.Message)" 'ERROR'; exit 1 }

if (-not $qsDatabases -or $qsDatabases.Count -eq 0) {
    Write-CollectorLog 'No databases with Query Store enabled found.'; exit 0
}

Write-CollectorLog "Starting Query Store collection — $($qsDatabases.Count) database(s) with QS enabled"

# Track which intervals have already been captured (to avoid duplicates on re-run)
$capturedIntervals = @{}
if (Test-Path $csvPath) {
    try {
        Import-Csv $csvPath -ErrorAction SilentlyContinue |
            Where-Object { $_.interval_start -and $_.database_name } |
            ForEach-Object { $capturedIntervals["$($_.database_name)|$($_.interval_start)"] = $true }
    } catch {}
}

$totalNew = 0
foreach ($db in $qsDatabases) {
    $dbName = $db.name
    try {
        $rows = @(Invoke-Sql -File $sqlScript -Db $dbName)
        if (-not $rows -or $rows.Count -eq 0) { continue }
        if ($rows[0].query_sql_text -in 'QUERY_STORE_DISABLED','NO_COMPLETED_INTERVAL') { continue }

        $newRows = @($rows | Where-Object {
            -not $capturedIntervals["$dbName|$($_.interval_start)"]
        })

        if ($newRows.Count -gt 0) {
            $newRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Append -Encoding UTF8
            $totalNew += $newRows.Count
            $capturedIntervals["$dbName|$($newRows[0].interval_start)"] = $true
        }
    } catch {
        Write-CollectorLog "Failed for database '$dbName': $($_.Exception.Message)" 'WARN'
    }
}

Write-CollectorLog "OK — $totalNew new row(s) appended across $($qsDatabases.Count) database(s)"