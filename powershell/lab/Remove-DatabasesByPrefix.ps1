<#
.SYNOPSIS
Drops SQL Server databases whose names start with a given prefix.

.NOTES
ScriptType   : automation
TargetScope  : single server
RiskLevel    : HIGH IMPACT — drops databases permanently
Purpose      : Lab cleanup — remove a batch of test or migration databases by prefix.

.DESCRIPTION
Sets each matching database to SINGLE_USER before dropping to force-disconnect active sessions.
Use -Force to skip the confirmation prompt. Use -Confirm to review before dropping.

.PARAMETER Prefix           Database name prefix to match. Defaults to 'migdb'.
.PARAMETER ServerInstance   Target SQL Server instance. Defaults to '.'.
.PARAMETER Force            Skip the confirmation prompt.
.PARAMETER Confirm          Show list and prompt before dropping.

.EXAMPLE
# Preview, then confirm interactively
pwsh -ExecutionPolicy Bypass -File .\powershell\lab\Remove-DatabasesByPrefix.ps1 -Prefix migdb -Confirm

.EXAMPLE
# Drop immediately without prompting
pwsh -ExecutionPolicy Bypass -File .\powershell\lab\Remove-DatabasesByPrefix.ps1 -Prefix migdb -Force
#>

param(
    [string]$Prefix         = 'migdb',
    [string]$ServerInstance = '.',
    [switch]$Force,
    [switch]$Confirm
)

$ErrorActionPreference = 'Stop'

$connStr = "Server=$ServerInstance;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"
$conn    = New-Object System.Data.SqlClient.SqlConnection $connStr

try {
    $conn.Open()

    $cmd             = $conn.CreateCommand()
    $cmd.CommandText = "SELECT name FROM sys.databases WHERE name LIKE @prefix + '%' ORDER BY name;"
    $cmd.Parameters.AddWithValue('@prefix', $Prefix) | Out-Null

    $reader = $cmd.ExecuteReader()
    $table  = New-Object System.Data.DataTable
    $table.Load($reader)

    if ($table.Rows.Count -eq 0) {
        Write-Host "No databases found with prefix '$Prefix'." -ForegroundColor Yellow
        return
    }

    Write-Host "Databases matching prefix '$Prefix':" -ForegroundColor Cyan
    foreach ($row in $table.Rows) { Write-Host "  - $($row['name'])" }

    if ($Confirm -and -not $Force) {
        $answer = Read-Host "`nDrop these $($table.Rows.Count) database(s)? (y/N)"
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    }
    elseif (-not $Force) {
        Write-Host 'Use -Force to drop without prompting or -Confirm to review first.' -ForegroundColor Yellow
        return
    }

    foreach ($row in $table.Rows) {
        $dbName          = $row['name']
        $drop            = $conn.CreateCommand()
        $drop.CommandText = "ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbName];"
        [void]$drop.ExecuteNonQuery()
        Write-Host "Dropped: $dbName" -ForegroundColor Yellow
    }

    Write-Host "`nDropped $($table.Rows.Count) database(s)." -ForegroundColor Green
}
finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
}
